module AdvancedHMC

using Statistics: mean, var, middle
using LinearAlgebra: Symmetric, UpperTriangular, mul!, ldiv!, dot, I, diag, cholesky, UniformScaling
using StatsFuns: logaddexp, logsumexp
using Random: GLOBAL_RNG, AbstractRNG
using ProgressMeter: ProgressMeter
using Parameters: @unpack, reconstruct
using ArgCheck: @argcheck

import StatsBase: sample

### Random

# Support of passing a vector of RNGs
Base.rand(rng::AbstractVector{<:AbstractRNG}) = rand.(rng)
Base.randn(rng::AbstractVector{<:AbstractRNG}) = randn.(rng)
function Base.rand(rng::AbstractVector{<:AbstractRNG}, T, n_chains::Int)
    @argcheck length(rng) == n_chains
    return rand.(rng, T)
end
function Base.randn(rng::AbstractVector{<:AbstractRNG}, T, dim::Int, n_chains::Int)
    @argcheck length(rng) == n_chains
    return cat(randn.(rng, T, dim)...; dims=2)
end

randcat_logp(rng::AbstractRNG, unnorm_ℓp::AbstractVector) =
    randcat(rng, exp.(unnorm_ℓp .- logsumexp(unnorm_ℓp)))
function randcat(rng::AbstractRNG, p::AbstractVector{T}) where {T}
    u = rand(rng, T)
    c = zero(eltype(p))
    i = 0
    while c < u
        c += p[i+=1]
    end
    return max(i, 1)
end

randcat_logp(rng::Union{AbstractRNG, AbstractVector{<:AbstractRNG}}, unnorm_ℓP::AbstractMatrix) =
    randcat(rng, exp.(unnorm_ℓP .- logsumexp(unnorm_ℓP; dims=2)))
function randcat(rng::Union{AbstractRNG, AbstractVector{<:AbstractRNG}}, P::AbstractMatrix{T}) where {T}
    u = rand(rng, T, size(P, 1))
    C = cumsum(P; dims=2)
    is = convert.(Int, vec(sum(C .< u; dims=2)))
    return max.(is, 1)
end

# Notations
# ℓπ: log density of the target distribution
# ∂ℓπ∂θ: gradient of the log density of the target distribution
# θ: position variables / model parameters
# r: momentum variables

include("adaptation/Adaptation.jl")
using .Adaptation
using .Adaptation: AbstractScalarOrVec
export NesterovDualAveraging, UnitMassMatrix, WelfordVar, WelfordCov, NaiveHMCAdaptor, StanHMCAdaptor

include("metric.jl")
export UnitEuclideanMetric, DiagEuclideanMetric, DenseEuclideanMetric
include("hamiltonian.jl")
export Hamiltonian
include("integrator.jl")
export Leapfrog, JitteredLeapfrog, TemperedLeapfrog
include("trajectory.jl")
export StaticTrajectory, HMCDA, NUTS, EndPointTS, SliceTS, MultinomialTS, ClassicNoUTurn, GeneralisedNoUTurn, find_good_eps
include("diagnosis.jl")
include("sampler.jl")
export sample

# Default adaptors

StepSizeAdaptor(δ::AbstractFloat, i::AbstractIntegrator) = NesterovDualAveraging(δ, nom_step_size(i))

import .Adaptation: NesterovDualAveraging
@deprecate NesterovDualAveraging(δ, i::AbstractIntegrator) StepSizeAdaptor(δ, i)
export NesterovDualAveraging

MassMatrixAdaptor(m::UnitEuclideanMetric{T}) where {T} = UnitMassMatrix(T)
MassMatrixAdaptor(m::DiagEuclideanMetric{T}) where {T} = WelfordVar(T, size(m); var=copy(m.M⁻¹))
MassMatrixAdaptor(m::DenseEuclideanMetric{T}) where {T} = WelfordCov(T, size(m); cov=copy(m.M⁻¹))

@deprecate Preconditioner(m::AbstractMatrix) MassMatrixAdaptor(m)

MassMatrixAdaptor(m::Type{TM}, sz::Tuple{Vararg{Int}}=(2,)) where {TM<:AbstractMetric} = MassMatrixAdaptor(Float64, m, sz)
MassMatrixAdaptor(::Type{T}, ::Type{TM}, sz::Tuple{Vararg{Int}}=(2,)) where {T<:AbstractFloat, TM<:AbstractMetric} = MassMatrixAdaptor(TM(T, sz))

export StepSizeAdaptor, MassMatrixAdaptor

### Init

using Requires

function __init__()
    include(joinpath(@__DIR__, "contrib/diffeq.jl"))
    include(joinpath(@__DIR__, "contrib/ad.jl"))
end

end # module
