using Images, SIUnits, Base.Test

img = load("test.imagine")
@test ndims(img) == 4
@test size(img) == (5,7,3,4)
@test timedim(img) == 4
@test spatialorder(img) == ["x", "l", "z"]
@test pixelspacing(img)[1:2] == [0.71e-6Meter, 0.71e-6Meter]
@test_approx_eq pixelspacing(img)[3].val (2/3)*1e-4

bn = tempname()
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
