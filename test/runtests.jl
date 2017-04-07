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
rm(ifn)
rm(cfn)

using ImagineFormat
io = IOBuffer()
imagine2nrrd(io, img["imagineheader"])
str = takebuf_string(io)
@test str == "NRRD0001\ntype: uint16\ndimension: 4\nsizes: 5 7 3 4\nkinds: space space space time\nencoding: raw\nendian: little\n"

# Optional fields
MHz = u"MHz"
μs = u"μs"
@test img["imagineheader"]["readout rate"] == img2["imagineheader"]["readout rate"] == 35.0MHz
@test img["imagineheader"]["vertical shift speed"] == img2["imagineheader"]["vertical shift speed"] == 1.9176μs

h = ImagineFormat.parse_header("test_noshift.imagine")
h["byte order"] = ENDIAN_BOM == 0x04030201 ? "l" : "b"
ImagineFormat.save_header(ifn, h)
h2 = ImagineFormat.parse_header(ifn)
@test isnan(h["readout rate"]) && isnan(h2["readout rate"])
@test isnan(h["vertical shift speed"]) && isnan(h2["vertical shift speed"])
rm(ifn)
