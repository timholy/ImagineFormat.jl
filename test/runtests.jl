using Images, FixedPointNumbers, Unitful, Base.Test

μm = u"μm"
img = load("test.imagine")
@test eltype(img) == N2f14
@test ndims(img) == 4
@test size(img) == (5,7,3,4)
@test timedim(img) == 4
@test axisnames(img) == (:x, :l, :z, :time)
@test pixelspacing(img)[1:2] == (0.71μm, 0.71μm)
@test pixelspacing(img)[3] ≈ 100μm
@test img.properties["imagineheader"]["bidirectional"] == false
imgb = load("test_bidi.imagine")
@test imgb.properties["imagineheader"]["bidirectional"] == true

bn = joinpath(tempdir(), randstring())
ifn = string(bn, ".imagine")
cfn = string(bn, ".cam")
A = rand(Float32,2,3,4,5)
open(cfn, "w") do io
    write(io, A)
end
ImagineFormat.save_header(ifn, "test.imagine", A)
img2 = load(ifn)
@test eltype(img2) == Float32
@test data(img2) == A

using ImagineFormat
io = IOBuffer()
imagine2nrrd(io, img["imagineheader"])
str = String(take!(io))
@test str == "NRRD0001\ntype: uint16\ndimension: 4\nsizes: 5 7 3 4\nkinds: space space space time\nencoding: raw\nendian: little\n"

# Optional fields
MHz = u"MHz"
μs = u"μs"
@test isnan(img["imagineheader"]["readout rate"]) && isnan(img2["imagineheader"]["readout rate"]) #marked as NA in test.imagine
@test img["imagineheader"]["vertical shift speed"] == img2["imagineheader"]["vertical shift speed"] == 1.9176μs

h = ImagineFormat.parse_header("test_noshift.imagine")
h["byte order"] = ENDIAN_BOM == 0x04030201 ? "l" : "b"
ImagineFormat.save_header(ifn, h)
h2 = ImagineFormat.parse_header(ifn)
@test isnan(h["readout rate"]) && isnan(h2["readout rate"])
@test isnan(h["vertical shift speed"]) && isnan(h2["vertical shift speed"])
rm(ifn)
img2 = 0
gc(); gc(); gc()
rm(cfn)

#test BidiImageArrays
A = ones(2,2,4,5)
zsize = size(A,3)
for t = 1:size(A,4)
    for z = 1:zsize
        if isodd(t)
            A[:,:,z,t] = z
        else
            A[:,:,z,t] = zsize-z+1
        end
    end
end

B = BidiImageArray(A)
for z = 1:zsize
    @test all(B[:,:,z,:].==z) #getindex
    B[:,:,z,:] = zsize-z+1 #setindex!
    @test all(B[:,:,z,:].==zsize-z+1)
end
