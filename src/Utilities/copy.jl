struct IndexMap
    varmap::Dict{MOI.VariableIndex, MOI.VariableIndex}
    conmap::Dict{MOI.ConstraintIndex, MOI.ConstraintIndex}
end
IndexMap() = IndexMap(Dict{MOI.VariableIndex, MOI.VariableIndex}(),
                 Dict{MOI.ConstraintIndex, MOI.ConstraintIndex}())
Base.getindex(idxmap::IndexMap, vi::MOI.VariableIndex) = idxmap.varmap[vi]
function Base.getindex(idxmap::IndexMap, ci::MOI.ConstraintIndex{F, S}) where {F, S}
    idxmap.conmap[ci]::MOI.ConstraintIndex{F, S}
end

Base.setindex!(idxmap::IndexMap, vi1::MOI.VariableIndex, vi2::MOI.VariableIndex) = Base.setindex!(idxmap.varmap, vi1, vi2)
function Base.setindex!(idxmap::IndexMap, ci1::MOI.ConstraintIndex{F, S}, ci2::MOI.ConstraintIndex{F, S}) where {F, S}
    Base.setindex!(idxmap.conmap, ci1, ci2)
end

Base.delete!(idxmap::IndexMap, vi::MOI.VariableIndex) = delete!(idxmap.varmap, vi)
Base.delete!(idxmap::IndexMap, ci::MOI.ConstraintIndex) = delete!(idxmap.conmap, ci)

Base.keys(idxmap::IndexMap) = Iterators.flatten((keys(idxmap.varmap), keys(idxmap.conmap)))

"""
    pass_attributes(dest::MOI.ModelLike, src::MOI.ModelLike, copy_names::Bool, idxmap::IndexMap, passattr!::Function=MOI.set)

Pass the model attributes from the model `src` to the model `dest` using `canpassattr` to check if the attribute can be passed and `passattr!` to pass the attribute. Does not copy `Name` if `copy_names` is `false`.

    pass_attributes(dest::MOI.ModelLike, src::MOI.ModelLike, copy_names::Bool, idxmap::IndexMap, vis_src::Vector{MOI.VariableIndex}, passattr!::Function=MOI.set)

Pass the variable attributes from the model `src` to the model `dest` using `canpassattr` to check if the attribute can be passed and `passattr!` to pass the attribute. Does not copy `VariableName` if `copy_names` is `false`.

    pass_attributes(dest::MOI.ModelLike, src::MOI.ModelLike, copy_names::Bool, idxmap::IndexMap, cis_src::Vector{MOI.ConstraintIndex{F, S}}, passattr!::Function=MOI.set) where {F, S}

Pass the constraint attributes of `F`-in-`S` constraints from the model `src` to the model `dest` using `canpassattr` to check if the attribute can be passed and `passattr!` to pass the attribute. Does not copy `ConstraintName` if `copy_names` is `false`.
"""
function pass_attributes end

function pass_attributes(dest::MOI.ModelLike, src::MOI.ModelLike, copy_names::Bool, idxmap::IndexMap, passattr!::Function=MOI.set)
    # Copy model attributes
    attrs = MOI.get(src, MOI.ListOfModelAttributesSet())
    _pass_attributes(dest, src, copy_names, idxmap, attrs, tuple(), tuple(), tuple(), passattr!)
end
function pass_attributes(dest::MOI.ModelLike, src::MOI.ModelLike, copy_names::Bool, idxmap::IndexMap, vis_src::Vector{VI}, passattr!::Function=MOI.set)
    # Copy variable attributes
    attrs = MOI.get(src, MOI.ListOfVariableAttributesSet())
    vis_dest = map(vi -> idxmap[vi], vis_src)
    _pass_attributes(dest, src, copy_names, idxmap, attrs, (VI,), (vis_src,), (vis_dest,), passattr!)
end
function pass_attributes(dest::MOI.ModelLike, src::MOI.ModelLike, copy_names::Bool, idxmap::IndexMap, cis_src::Vector{CI{F, S}}, passattr!::Function=MOI.set) where {F, S}
    # Copy constraint attributes
    attrs = MOI.get(src, MOI.ListOfConstraintAttributesSet{F, S}())
    cis_dest = map(ci -> idxmap[ci], cis_src)
    _pass_attributes(dest, src, copy_names, idxmap, attrs, (CI{F, S},), (cis_src,), (cis_dest,), passattr!)
end

function _pass_attributes(dest::MOI.ModelLike, src::MOI.ModelLike, copy_names::Bool, idxmap::IndexMap, attrs, canargs, getargs, setargs, passattr!::Function=MOI.set)
    for attr in attrs
        @assert MOI.is_copyable(attr)
        if (copy_names || !(attr isa MOI.Name || attr isa MOI.VariableName || attr isa MOI.ConstraintName))
            passattr!(dest, attr, setargs..., attribute_value_map(idxmap, MOI.get(src, attr, getargs...)))
        end
    end
end

"""
    copyconstraints!(dest::MOI.ModelLike, src::MOI.ModelLike, copy_names::Bool, idxmap::IndexMap, ::Type{F}, ::Type{S}) where {F<:MOI.AbstractFunction, S<:MOI.AbstractSet}

Copy the constraints of type `F`-in-`S` from the model `src` the model `dest` and fill `idxmap` accordingly. Does not copy `ConstraintName` if `copy_names` is `false`.
"""
function copyconstraints!(dest::MOI.ModelLike, src::MOI.ModelLike, copy_names::Bool, idxmap::IndexMap, ::Type{F}, ::Type{S}) where {F<:MOI.AbstractFunction, S<:MOI.AbstractSet}
    # Copy constraints
    cis_src = MOI.get(src, MOI.ListOfConstraintIndices{F, S}())
    for ci_src in cis_src
        f_src = MOI.get(src, MOI.ConstraintFunction(), ci_src)
        f_dest = mapvariables(idxmap, f_src)
        s = MOI.get(src, MOI.ConstraintSet(), ci_src)
        ci_dest = MOI.add_constraint(dest, f_dest, s)
        idxmap.conmap[ci_src] = ci_dest
    end

    pass_attributes(dest, src, copy_names, idxmap, cis_src)
end

attribute_value_map(idxmap, f::MOI.AbstractFunction) = mapvariables(idxmap, f)
attribute_value_map(idxmap, attribute_value) = attribute_value
function default_copy_to(dest::MOI.ModelLike, src::MOI.ModelLike)
    Base.depwarn("default_copy_to(dest, src) is deprecated, use default_copy_to(dest, src, true) instead or default_copy_to(dest, src, false) if you do not want to copy names.", :default_copy_to)
    default_copy_to(dest, src, true)
end
function default_copy_to(dest::MOI.ModelLike, src::MOI.ModelLike, copy_names::Bool)
    MOI.empty!(dest)

    idxmap = IndexMap()

    # Copy variables
    vis_src = MOI.get(src, MOI.ListOfVariableIndices())
    for vi in vis_src
        idxmap.varmap[vi] = MOI.add_variable(dest)
    end

    # Copy variable attributes
    pass_attributes(dest, src, copy_names, idxmap, vis_src)

    # Copy model attributes
    pass_attributes(dest, src, copy_names, idxmap)

    # Copy constraints
    for (F, S) in MOI.get(src, MOI.ListOfConstraints())
        # do the rest in copyconstraints! which is type stable
        copyconstraints!(dest, src, copy_names, idxmap, F, S)
    end

    return idxmap
end

# Allocate-Load Interface: 2-pass copy of a MathOptInterface model
# Some solver wrappers (e.g. SCS, ECOS, SDOI) do not supporting copying an optimization model using `MOI.add_constraints`, `MOI.add_variables` and `MOI.set`
# as they first need to figure out some information about a model before being able to pass the problem data to the solver.
#
# During the first pass (called allocate) : the model collects the relevant information about the problem so that
# on the second pass (called load), the constraints can be loaded directly to the solver (in case of SDOI) or written directly into the matrix of constraints (in case of SCS and ECOS).

# To support `MOI.copy_to` using this 2-pass mechanism, implement the allocate-load interface defined below and do:
# MOI.copy_to(dest::ModelType, src::MOI.ModelLike) = MOIU.allocate_load(dest, src)
# In the implementation of the allocate-load interface, it can be assumed that the different functions will the called in the following order:
# 1) `allocate_variables`
# 2) `allocate` and `allocate_constraint`
# 3) `load_variables` and `allocate_constraint`
# 4) `load` and `load_constraint`
# The interface is not meant to be used to create new constraints with `allocate_constraint` followed by `load_constraint` after a solve, it is only meant for being used in this order to implement `MOI.copy_to`.

"""
    needs_allocate_load(model::MOI.ModelLike)::Bool

Return a `Bool` indicating whether `model` does not support `add_variables`/`add_constraint`/`set` but supports `allocate_variables`/`allocate_constraint`/`allocate`/`load_variables`/`load_constraint`/`load`.
That is, the allocate-load interface need to be used to copy an model to `model`.
"""
needs_allocate_load(::MOI.ModelLike) = false

"""
    allocate_variables(model::MOI.ModelLike, nvars::Integer)

Creates `nvars` variables and returns a vector of `nvars` variable indices.
"""
function allocate_variables end

"""
    allocate(model::ModelLike, attr::ModelLikeAttribute, value)
    allocate(model::ModelLike, attr::AbstractVariableAttribute, v::VariableIndex, value)
    allocate(model::ModelLike, attr::AbstractConstraintAttribute, c::ConstraintIndex, value)

Informs `model` that `load` will be called with the same arguments after `load_variables` is called.
"""
function allocate end

function allocate(model::MOI.ModelLike, attr::Union{MOI.AbstractVariableAttribute, MOI.AbstractConstraintAttribute}, indices::Vector, values::Vector)
    for (index, value) in zip(indices, values)
        allocate(model, attr, index, value)
    end
end

"""
    allocate_constraint(model::MOI.ModelLike, f::MOI.AbstractFunction, s::MOI.AbstractSet)

Returns the index for the constraint to be used in `load_constraint` that will be called after `load_variables` is called.
"""
function allocate_constraint end

"""
    load_variables(model::MOI.ModelLike, nvars::Integer)

Prepares the `model` for `loadobjective!` and `load_constraint`.
"""
function load_variables end

"""
    load(model::ModelLike, attr::ModelLikeAttribute, value)
    load(model::ModelLike, attr::AbstractVariableAttribute, v::VariableIndex, value)
    load(model::ModelLike, attr::AbstractConstraintAttribute, c::ConstraintIndex, value)

This has the same effect that `set` with the same arguments except that `allocate` should be called first before `load_variables`.
"""
function load end

function load(model::MOI.ModelLike, attr::Union{MOI.AbstractVariableAttribute, MOI.AbstractConstraintAttribute}, indices::Vector, values::Vector)
    for (index, value) in zip(indices, values)
        load(model, attr, index, value)
    end
end

"""
    load_constraint(model::MOI.ModelLike, ci::MOI.ConstraintIndex, f::MOI.AbstractFunction, s::MOI.AbstractSet)

Sets the constraint function and set for the constraint of index `ci`.
"""
function load_constraint end

function allocate_constraints(dest::MOI.ModelLike, src::MOI.ModelLike, copy_names::Bool, idxmap::IndexMap, ::Type{F}, ::Type{S}) where {F<:MOI.AbstractFunction, S<:MOI.AbstractSet}
    # Allocate constraints
    cis_src = MOI.get(src, MOI.ListOfConstraintIndices{F, S}())

    for ci_src in cis_src
        f_src = MOI.get(src, MOI.ConstraintFunction(), ci_src)
        s = MOI.get(src, MOI.ConstraintSet(), ci_src)
        f_dest = mapvariables(idxmap, f_src)
        ci_dest = allocate_constraint(dest, f_dest, s)
        idxmap.conmap[ci_src] = ci_dest
    end

    return pass_attributes(dest, src, copy_names, idxmap, cis_src, allocate)
end

function load_constraints(dest::MOI.ModelLike, src::MOI.ModelLike, copy_names::Bool, idxmap::IndexMap, ::Type{F}, ::Type{S}) where {F<:MOI.AbstractFunction, S<:MOI.AbstractSet}
    # Load constraints
    cis_src = MOI.get(src, MOI.ListOfConstraintIndices{F, S}())
    for ci_src in cis_src
        ci_dest = idxmap[ci_src]
        f_src = MOI.get(src, MOI.ConstraintFunction(), ci_src)
        f_dest = mapvariables(idxmap, f_src)
        s = MOI.get(src, MOI.ConstraintSet(), ci_src)
        load_constraint(dest, ci_dest, f_dest, s)
    end

    return pass_attributes(dest, src, copy_names, idxmap, cis_src, load)
end

"""
    allocate_load(dest::MOI.ModelLike, src::MOI.ModelLike)

Implements `MOI.copy_to(dest, src)` using the allocate-load interface.
"""
function allocate_load(dest::MOI.ModelLike, src::MOI.ModelLike, copy_names::Bool)
    MOI.empty!(dest)

    idxmap = IndexMap()

    # Allocate variables
    nvars = MOI.get(src, MOI.NumberOfVariables())
    vis_src = MOI.get(src, MOI.ListOfVariableIndices())
    vis_dest = allocate_variables(dest, nvars)
    for (var_src, var_dest) in zip(vis_src, vis_dest)
        idxmap.varmap[var_src] = var_dest
    end

    # Allocate variable attributes
    pass_attributes(dest, src, copy_names, idxmap, vis_src, allocate)

    # Allocate model attributes
    pass_attributes(dest, src, copy_names, idxmap, allocate)

    # Allocate constraints
    for (F, S) in MOI.get(src, MOI.ListOfConstraints())
        # do the rest in copyconstraints! which is type stable
        allocate_constraints(dest, src, copy_names, idxmap, F, S)
    end

    # Load variables
    load_variables(dest, nvars)

    # Load variable attributes
    pass_attributes(dest, src, copy_names, idxmap, vis_src, load)

    # Load model attributes
    pass_attributes(dest, src, copy_names, idxmap, load)

    # Copy constraints
    for (F, S) in MOI.get(src, MOI.ListOfConstraints())
        # do the rest in copyconstraints! which is type stable
        load_constraints(dest, src, copy_names, idxmap, F, S)
    end

    return idxmap
end
