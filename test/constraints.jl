@testset "Scalar constraints" begin
    model = Model{Float64}()
    x = MOI.add_variable(model)
    @testset "SingleVariable" begin
        f = MOI.SingleVariable(x)
        ci = MOIU.add_scalar_constraint(model, f, MOI.EqualTo(1.0))
        @test MOI.get(model, MOI.ConstraintFunction(), ci) == f
        @test MOI.get(model, MOI.ConstraintSet(), ci) == MOI.EqualTo(1.0)
    end
    @testset "ScalarAffineFunction" begin
        f = MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1.0, x)], 2.0)
        g = MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1.0, x)], 0.0)
        ci = MOIU.add_scalar_constraint(model, f, MOI.EqualTo(3.0))
        @test f.constant == 2.0
        @test MOI.get(model, MOI.ConstraintFunction(), ci) ≈ g
        @test MOI.get(model, MOI.ConstraintSet(), ci) == MOI.EqualTo(1.0)
        ci = MOIU.add_scalar_constraint(model, f, MOI.Interval(-1.0, 1.0))
        @test f.constant == 2.0
        @test MOI.get(model, MOI.ConstraintFunction(), ci) ≈ g
        @test MOI.get(model, MOI.ConstraintSet(), ci) == MOI.Interval(-3.0,
                                                                      -1.0)
    end
end
