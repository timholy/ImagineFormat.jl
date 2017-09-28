import Base: size, getindex, setindex!

#z indices are flipped for even-numbered timepoints
struct BidiImageArray{T} <: AbstractArray{T,4}
    A::AbstractArray{T,4}
    z_size::Int
end

BidiImageArray(A::AbstractArray{T,4}) where {T} = BidiImageArray(A, size(A,3))

size(B::BidiImageArray) = size(B.A)

Base.IndexStyle(::Type{<:BidiImageArray}) = IndexCartesian()

function getindex(B::BidiImageArray{T}, I::Vararg{Int, 4}) where {T}
    t_ind = I[4]
    if isodd(t_ind)
        return getindex(B.A, I...)
    else
        return getindex(B.A, I[1], I[2], B.z_size - I[3] + 1, t_ind)
    end
end

function setindex!(B::BidiImageArray{T}, v, I::Vararg{Int, 4}) where {T}
    t_ind = I[4]
    if isodd(t_ind)
        return setindex!(B.A, v, I...)
    else
        return setindex!(B.A, v, I[1], I[2], B.z_size - I[3] + 1, I[4])
    end
end
