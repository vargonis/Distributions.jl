
# "Generating gamma variates by a modified rejection technique"
# J.H. Ahrens, U. Dieter
# Communications of the ACM, Vol 25(1), 1982, pp 47-54
# doi:10.1145/358315.358390

# suitable for shape >= 1.0

struct GammaGDSampler{T<:Real} <: Sampleable{Univariate,Continuous}
    a::T
    s2::T
    s::T
    i2s::T
    d::T
    q0::T
    b::T
    σ::T
    c::T
    scale::T
end

function GammaGDSampler(g::Gamma{T}) where {T}
    a = shape(g)
    # Step 1
    s2 = a - 0.5
    s = sqrt(s2)
    i2s = 0.5/s
    d = 5.656854249492381 - 12.0s # 4*sqrt(2) - 12s

    # Step 4
    ia = 1.0/a
    q0 = ia*@horner(ia,
                    0.0416666664,
                    0.0208333723,
                    0.0079849875,
                    0.0015746717,
                    -0.0003349403,
                    0.0003340332,
                    0.0006053049,
                    -0.0004701849,
                    0.0001710320)

    if a <= 3.686
        b = 0.463 + s + 0.178s2
        σ = 1.235
        c = 0.195/s - 0.079 + 0.16s
    elseif a <= 13.022
        b = 1.654 + 0.0076s2
        σ = 1.68/s + 0.275
        c = 0.062/s + 0.024
    else
        b = 1.77
        σ = 0.75
        c = 0.1515/s
    end

    GammaGDSampler(T(a), T(s2), T(s), T(i2s), T(d), T(q0), T(b), T(σ), T(c), scale(g))
end

function calc_q(s::GammaGDSampler, t)
    v = t*s.i2s
    if abs(v) > 0.25
        return s.q0 - s.s*t + 0.25*t*t + 2.0*s.s2*log1p(v)
    else
        return s.q0 + 0.5*t*t*(v*@horner(v,
                                         0.333333333,
                                         -0.249999949,
                                         0.199999867,
                                         -0.1666774828,
                                         0.142873973,
                                         -0.124385581,
                                         0.110368310,
                                         -0.112750886,
                                         0.10408986))
    end
end

function rand(rng::AbstractRNG, s::GammaGDSampler{T}) where T
    # Step 2
    t = randn(rng, T)
    x = s.s + 0.5t
    t >= 0.0 && return x*x*s.scale

    # Step 3
    u = rand(rng, T)
    s.d*u <= t*t*t && return x*x*s.scale

    # Step 5
    if x > 0.0
        # Step 6
        q = calc_q(s, t)
        # Step 7
        log1p(-u) <= q && return x*x*s.scale
    end

    # Step 8
    t = 0.0
    while true
        e = 0.0
        u = 0.0
        while true
            e = randexp(rng, T)
            u = 2.0rand(rng, T) - 1.0
            t = s.b + e*s.σ*sign(u)
            # Step 9
            t ≥ -0.718_744_837_717_19 && break
        end

        # Step 10
        q = calc_q(s, t)

        # Step 11
        (q > 0.0) && (s.c*abs(u) ≤ expm1(q)*exp(e-0.5t*t)) && break
    end

    # Step 12
    x = s.s+0.5t
    return x*x*s.scale
end

# "Computer methods for sampling from gamma, beta, poisson and bionomial distributions"
# J.H. Ahrens and U. Dieter
# Computing, 1974, Volume 12(3), pp 223-246
# doi:10.1007/BF02293108

# valid for 0 < shape <= 1
struct GammaGSSampler{T<:Real} <: Sampleable{Univariate,Continuous}
    a::T
    ia::T
    b::T
    scale::T
end

function GammaGSSampler(d::Gamma{T}) where T
    a = shape(d)
    ia = one(T) / a
    b = one(T) + T(0.36787944117144233) * a
    GammaGSSampler{T}(a, ia, b, scale(d))
end

function rand(rng::AbstractRNG, s::GammaGSSampler{T}) where T
    while true
        # step 1
        p = s.b*rand(rng, T)
        e = randexp(rng, T)
        if p <= 1.0
            # step 2
            x = exp(log(p)*s.ia)
            e < x || return s.scale*x
        else
            # step 3
            x = -log(s.ia*(s.b-p))
            e < log(x)*(1.0-s.a) || return s.scale*x
        end
    end
end


# "A simple method for generating gamma variables"
# G. Marsaglia and W.W. Tsang
# ACM Transactions on Mathematical Software (TOMS), 2000, Volume 26(3), pp. 363-372
# doi:10.1145/358407.358414
# http://www.cparity.com/projects/AcmClassification/samples/358414.pdf

struct GammaMTSampler{T<:Real} <: Sampleable{Univariate,Continuous}
    d::T
    c::T
    κ::T
end

function GammaMTSampler(g::Gamma{T}) where T
    d = shape(g) - one(T)/3
    c = one(T) / sqrt(9d)
    κ = d * scale(g)
    GammaMTSampler{T}(d, c, κ)
end

function rand(rng::AbstractRNG, s::GammaMTSampler{T}) where T
    while true
        x = randn(rng, T)
        v = one(T) + s.c * x
        while v <= zero(T)
            x = randn(rng, T)
            v = one(T) + s.c * x
        end
        v *= (v * v)
        u = rand(rng, T)
        x2 = x * x
        if u < one(T) - T(0.331) * abs2(x2) || log(u) < x2/2 + s.d * (one(T) - v + log(v))
            return v*s.κ
        end
    end
end

# Inverse Power sampler
# uses the x*u^(1/a) trick from Marsaglia and Tsang (2000) for when shape < 1
struct GammaIPSampler{S<:Sampleable{Univariate,Continuous}, T<:Real} <: Sampleable{Univariate,Continuous}
    s::S #sampler for Gamma(1+shape,scale)
    nia::T #-1/scale
end

function GammaIPSampler(d::Gamma{T}, ::Type{S}) where {T, S<:Sampleable}
    GammaIPSampler(Gamma{T}(one(T) + shape(d), scale(d)), -one(T) / shape(d))
end
GammaIPSampler(d::Gamma) = GammaIPSampler(d, GammaMTSampler)

function rand(rng::AbstractRNG, s::GammaIPSampler{S,T}) where {S,T}
    x = rand(rng, s.s)
    e = randexp(rng, T)
    x*exp(s.nia*e)
end

# function sampler(d::Gamma)
#     if d.shape < 1.0
#         # TODO: d.shape = 0.5 : use scaled chisq
#         GammaIPSampler(d)
#     elseif d.shape == 1.0
#         Exponential(d.scale)
#     else
#         GammaGDSampler(d)
#     end
# end
