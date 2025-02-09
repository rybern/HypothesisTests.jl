# Wilcoxon.jl
# Wilcoxon rank sum (Mann-Whitney U) and signed rank tests in Julia
#
# Copyright (C) 2012   Simon Kornblith
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

export MannWhitneyUTest, ExactMannWhitneyUTest, ApproximateMannWhitneyUTest

## COMMON MANN-WHITNEY U

# Automatic exact/normal selection
function MannWhitneyUTest{S<:Real,T<:Real}(x::AbstractVector{S}, y::AbstractVector{T})
    (U, ranks, tieadj, nx, ny, median) = mwustats(x, y)
    if nx + ny <= 10 || (nx + ny <= 50 && tieadj == 0)
        ExactMannWhitneyUTest(U, ranks, tieadj, nx, ny, median)
    else
        ApproximateMannWhitneyUTest(U, ranks, tieadj, nx, ny, median)
    end
end

# Get U, ranks, and tie adjustment for Mann-Whitney U test
function mwustats{S<:Real,T<:Real}(x::AbstractVector{S}, y::AbstractVector{T})
    nx = length(x)
    ny = length(y)
    if nx <= ny
        (ranks, tieadj) = tiedrank_adj([x; y])
        U = sum(ranks[1:nx]) - nx*(nx+1)/2
    else
        (ranks, tieadj) = tiedrank_adj([y; x])
        U = nx*ny - sum(ranks[1:ny]) + ny*(ny+1)/2
    end
    (U, ranks, tieadj, nx, ny, median(x)-median(y))
end


## EXACT MANN-WHITNEY U TEST

immutable ExactMannWhitneyUTest{T<:Real} <: HypothesisTest
    U::Float64              # test statistic: Mann-Whitney-U statistic
    ranks::Vector{Float64}  # ranks
    tie_adjustment::Float64 # adjustment for ties
    nx::Int                 # number of observations
    ny::Int
    median::T               # sample median
end
ExactMannWhitneyUTest{S<:Real,T<:Real}(x::AbstractVector{S}, y::AbstractVector{T}) =
    ExactMannWhitneyUTest(mwustats(x, y)...)

testname(::ExactMannWhitneyUTest) = "Exact Mann-Whitney U test"
population_param_of_interest(x::ExactMannWhitneyUTest) = ("Location parameter (pseudomedian)", 0, x.median) # parameter of interest: name, value under h0, point estimate

function show_params(io::IO, x::ExactMannWhitneyUTest, ident)
    println(io, ident, "number of observations in each group: ", [x.nx, x.ny])
    println(io, ident, "Mann-Whitney-U statistic:             ", x.U)
    println(io, ident, "rank sums:                            ", [sum(x.ranks[1:x.nx]), sum(x.ranks[x.nx+1:end])])
    println(io, ident, "adjustment for ties:                  ", x.tie_adjustment)
end

# Enumerate all possible Mann-Whitney U results for a given vector,
# determining left-and right-tailed p values
function mwuenumerate(x::ExactMannWhitneyUTest)
    # Get the other U if inverted by mwu_stats
    n = min(x.nx, x.ny)
    if x.ny > x.nx
        U = x.nx*x.ny - U
    end
    le = 0
    gr = 0
    tot = 0
    k = n*(n+1)/2
    for comb in combinations(x.ranks, n)
        Up = sum(comb) - k
        tot += 1
        le += Up <= x.U
        gr += Up >= x.U
    end
    (le/tot, gr/tot)
end

function pvalue(x::ExactMannWhitneyUTest; tail=:both) 
    if x.tie_adjustment == 0
        # Compute exact p-value using method from Rmath, which is fast but
        # cannot account for ties
        if tail == :both
            if x.U < x.nx * x.ny / 2
                2 * pwilcox(x.U, x.nx, x.ny, true)
            else
                2 * pwilcox(x.U - 1, x.nx, x.ny, false)
            end
        elseif tail == :left
            pwilcox(x.U, x.nx, x.ny, true)
        elseif tail == :right
            pwilcox(x.U - 1, x.nx, x.ny, false)
        else
            throw(ArgumentError("tail=$(tail) is invalid"))
        end
    else
        # Compute exact p-value by enumerating possible ranks in the tied data
        if tail == :both
            min(1, 2 * minimum(mwuenumerate(x)))
        elseif tail == :left
            mwuenumerate(x)[1]
        elseif tail == :right
            mwuenumerate(x)[2]
        else
            throw(ArgumentError("tail=$(tail) is invalid"))
        end
    end
end


## APPROXIMATE MANN-WHITNEY U TEST

immutable ApproximateMannWhitneyUTest{T<:Real} <: HypothesisTest
    U::Float64              # test statistic: Mann-Whitney-U statistic
    ranks::Vector{T}        # ranks
    tie_adjustment::Float64 # adjustment for ties
    nx::Int                 # number of observations
    ny::Int
    median::Float64         # sample median
    mu::Float64             # normal approximation: mean
    sigma::Float64          # normal approximation: std
end
function ApproximateMannWhitneyUTest{T<:Real}(U::Real, ranks::AbstractVector{T}, tie_adjustment::Real,
                                     nx::Int, ny::Int, median::Float64)
    mu = U - nx * ny / 2
    sigma = sqrt((nx * ny * (nx + ny + 1 - tie_adjustment /
        ((nx + ny) * (nx + ny - 1)))) / 12)
    ApproximateMannWhitneyUTest(U, ranks, tie_adjustment, nx, ny, median, mu, sigma)
end
ApproximateMannWhitneyUTest{S<:Real,T<:Real}(x::AbstractVector{S}, y::AbstractVector{T}) =
    ApproximateMannWhitneyUTest(mwustats(x, y)...)

testname(::ApproximateMannWhitneyUTest) = "Approximate Mann-Whitney U test"
population_param_of_interest(x::ApproximateMannWhitneyUTest) = ("Location parameter (pseudomedian)", 0, x.median) # parameter of interest: name, value under h0, point estimate

function show_params(io::IO, x::ApproximateMannWhitneyUTest, ident)
    println(io, ident, "number of observations in each group: ", [x.nx, x.ny])
    println(io, ident, "Mann-Whitney-U statistic:             ", x.U)
    println(io, ident, "rank sums:                            ", [sum(x.ranks[1:x.nx]), sum(x.ranks[x.nx+1:end])])
    println(io, ident, "adjustment for ties:                  ", x.tie_adjustment)
    println(io, ident, "normal approximation (μ, σ):          ", (x.mu, x.sigma))
end

function pvalue(x::ApproximateMannWhitneyUTest; tail=:both) 
    if x.mu == x.sigma == 0
        1
    else
        if tail == :both
            2 * ccdf(Normal(), abs(x.mu - 0.5 * sign(x.mu))/x.sigma)
        elseif tail == :left
            cdf(Normal(), (x.mu + 0.5)/x.sigma)
        elseif tail == :right
            ccdf(Normal(), (x.mu - 0.5)/x.sigma)
        end
    end
end


## helper: libRmath

@rmath_deferred_free(signrank)
function psignrank(q::Number, p1::Number, lower_tail::Bool,
                   log_p::Bool=false)
    signrank_deferred_free()
    ccall((:psignrank,libRmath), Float64, (Float64,Float64,Int32,Int32), q, p1,
          lower_tail, log_p)
end

