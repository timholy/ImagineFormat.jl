__precompile__()

module ImagineFormat

using Images, FileIO
using SIUnits, SIUnits.ShortUnits
# using FileIO: skipmagic, stream, @format_str, Stream

export imagine2nrrd, Micron

Micron = SIUnits.NonSIUnit{typeof(Meter),:µm}()
convert(::Type{SIUnits.SIQuantity},::typeof(Micron)) = Micro*Meter

function load(f::File{format"Imagine"}; mode="r")
    fabs = File(format"Imagine", abspath(f.filename))
    open(fabs) do s
        skipmagic(s)
        load(s, mode=mode)
    end
end

function load(io::Stream{format"Imagine"}; mode="r")
    s = stream(io)
    h = parse_header(s)
    filename = s.name[7:end-1]
    basename, ext = splitext(filename)
    camfilename = basename*".cam"
    T = h["pixel data type"]
    sz = [h["image width"], h["image height"], h["frames per stack"], h["nStacks"]]
    if sz[4] == 1
        sz = sz[1:3]
        if sz[3] == 1
            sz = sz[1:2]
        end
    end
    havez = h["frames per stack"] > 1
    havet = h["nStacks"] > 1
    # Check that the file size is consistent with the expected size
    if !isfile(camfilename)
        warn("Cannot open ", camfilename)
        data = Array(T, sz[1], sz[2], sz[3], 0)
    else
        fsz = filesize(camfilename)
        n_stacks = sz[end]
        if fsz != sizeof(T)*prod(map(Int64,sz))  # guard against overflow on 32bit
            warn("Size of image file is different from expected value")
            n_stacks = ifloor(fsz / sizeof(T) / prod(sz[1:end-1]))
        end
        if sizeof(T)*prod(map(Int64,sz[1:end-1]))*n_stacks > typemax(UInt)
            warn("File size is too big to mmap on 32bit")
            n_stacks = ifloor(fsz / sizeof(T) / typemax(UInt))
        end
        if n_stacks < sz[end]
            println("Truncating to ", n_stacks, length(sz) == 4 ? " stacks" : " frames")
            sz[end] = n_stacks
        end
        data = SharedArray(camfilename, T, tuple(sz...), mode=mode)
    end
    um_per_pixel = h["um per pixel"]*µm
    pstart = h["piezo"]["stop position"]
    pstop = h["piezo"]["start position"]
    if length(sz)>2
        dz = abs(pstart - pstop)/sz[3]
    else dz = 0.0 end

    props = Dict(
        "spatialorder" => (havez ? ["x", "l", "z"] : ["x", "l"]),
        "colorspace" => "Gray",
        "pixelspacing" => (havez ? [um_per_pixel, um_per_pixel, dz] : [um_per_pixel, um_per_pixel]),
        "limits" => (UInt16(0), UInt16(2^h["original image depth"]-1)),
        "imagineheader" => h,
        "suppress" => Set(Any["imagineheader"]))
    if havet
        props["timedim"] = havez ? 4 : 3
    end
    Image(data, props)
end

abstract Endian
type LittleEndian <: Endian; end
type BigEndian <: Endian; end
const endian_dict = Dict("l"=>LittleEndian, "b"=>BigEndian)
const nrrd_endian_dict = Dict(LittleEndian=>"little",BigEndian=>"big")
parse_endian(s::ASCIIString) = endian_dict[lowercase(s)]

function parse_vector_int(s::AbstractString)
    ss = split(s, r"[ ,;]", keep=false)
    v = Array(Int, length(ss))
    for i = 1:length(ss)
        v[i] = parse(Int,ss[i])
    end
    return v
end

const bitname_dict = Dict(
  "int8"      => Int8,
  "uint8"     => UInt8,
  "int16"     => Int16,
  "uint16"    => UInt16,
  "int32"     => Int32,
  "uint32"    => UInt32,
  "int64"     => Int64,
  "uint64"    => UInt64,
  "float16"   => Float16,
  "float32"   => Float32,
  "single"    => Float32,
  "float64"   => Float64,
  "double"    => Float64)

parse_bittypename(s::ASCIIString) = bitname_dict[lowercase(s)]

function float64_or_empty(s::ASCIIString)
    if isempty(s)
        return NaN
    else
        return parse(Float64,s)
    end
end

function parse_quantity_or_empty(s::ASCIIString)
    if isempty(s)
        return NaN
    else
        return parse_quantity(s)
    end
end

_unit_string_dict = Dict("um" => Micro*Meter, "s" => Second, "us" => Micro*Second, "MHz" => Mega*Hertz)
function parse_quantity(s::AbstractString, strict::Bool = true)
    # Find the last character of the numeric component
    m = match(r"[0-9\.\+-](?![0-9\.\+-])", s)
    if m == nothing
        error("AbstractString does not have a 'value unit' structure")
    end
    val = parse(Float64, s[1:m.offset])
    ustr = strip(s[m.offset+1:end])
    if isempty(ustr)
        if strict
            error("AbstractString does not have a 'value unit' structure")
        else
            return val
        end
    end
    val * _unit_string_dict[ustr]
end

# Read and parse a *.imagine file (an Imagine header file)
const compound_fields = Any["piezo", "binning"]
const field_key_dict = Dict{AbstractString,Function}(
    "header version"               => x->parse(Float64,x),
    "app version"                  => identity,
    "date and time"                => identity,
    "rig"                          => identity,
    "byte order"                   => parse_endian,
    "stimulus file content"        => identity,  # stimulus info parsed separately
    "comment"                      => identity,
    "ai data file"                 => identity,
    "image data file"              => identity,
    "start position"               => parse_quantity,
    "stop position"                => parse_quantity,
    "bidirection"                  => x->parse(Int,x) != 0,
    "output scan rate"             => x->parse_quantity(x, false),
    "nscans"                       => x->parse(Int,x),
    "channel list"                 => parse_vector_int,
    "label list"                   => identity,
    "scan rate"                    => x->parse_quantity(x, false),
    "min sample"                   => x->parse(Int,x),
    "max sample"                   => x->parse(Int,x),
    "min input"                    => x->parse(Float64,x),
    "max input"                    => x->parse(Float64,x),
    "original image depth"         => x->parse(Int,x),
    "saved image depth"            => x->parse(Int,x),
    "image width"                  => x->parse(Int,x),
    "image height"                 => x->parse(Int,x),
    "number of frames requested"   => x->parse(Int,x),
    "nStacks"                      => x->parse(Int,x),
    "idle time between stacks"     => parse_quantity,
    "pre amp gain"                 => float64_or_empty,
    "EM gain"                      => float64_or_empty,
    "gain"                         => float64_or_empty,
    "exposure time"                => parse_quantity,
    "vertical shift speed"         => parse_quantity_or_empty,
    "vertical clock vol amp"       => x->parse(Float64,x),
    "readout rate"                 => parse_quantity_or_empty,
    "pixel order"                  => identity,
    "frame index offset"           => x->parse(Int,x),
    "frames per stack"             => x->parse(Int,x),
    "pixel data type"              => parse_bittypename,
    "camera"                       => identity,
    "um per pixel"                 => x->parse(Float64,x),
    "hbin"                         => x->parse(Int,x),
    "vbin"                         => x->parse(Int,x),
    "hstart"                       => x->parse(Int,x),
    "hend"                         => x->parse(Int,x),
    "vstart"                       => x->parse(Int,x),
    "vend"                         => x->parse(Int,x),
    "angle from horizontal (deg)"  => float64_or_empty)

function parse_header(s::IOStream)
    headerdict = Dict{ASCIIString, Any}()
    for this_line = eachline(s)
        this_line = strip(this_line)
        if !isempty(this_line) && !ismatch(r"\[.*\]", this_line)
            # Split on =
            m = match(r"=", this_line)
            if m.offset < 2
                error("Line does not contain =")
            end
            k = this_line[1:m.offset-1]
            v = this_line[m.offset+1:end]
            if in(k, compound_fields)
                thisdict = Dict{ASCIIString, Any}()
                # Split on semicolon
                strs = split(v, r";")
                for i = 1:length(strs)
                    substrs = split(strs[i], r":")
                    @assert length(substrs) == 2
                    k2 = strip(substrs[1])
                    func = field_key_dict[k2]
                    v2 = strip(substrs[2])
                    try
                        thisdict[k2] = func(v2)
                    catch err
                        println("Error processing key '", k2, "' with value ", v2)
                        rethrow(err)
                    end
                end
                headerdict[k] = thisdict
            else
                func = field_key_dict[k]
                try
                    headerdict[k] = func(v)
                catch err
                    println("Error processing key ", k, " with value ", v)
                    rethrow(err)
                end
            end
        end
    end
    return headerdict
end
function parse_header(io::Stream{format"Imagine"})
    skipmagic(io)
    parse_header(stream(io))
end
function parse_header(f::File{format"Imagine"})
    open(f) do io
        parse_header(io)
    end
end
parse_header(filename::AbstractString) = parse_header(query(filename))

function imagine2nrrd(sheader::IO, h::Dict{ASCIIString, Any}, datafilename = nothing)
    println(sheader, "NRRD0001")
    T = h["pixel data type"]
    if T<:AbstractFloat
        println(sheader, "type: ", (T == Float32) ? "float" : "double")
    else
        println(sheader, "type: ", lowercase(string(T)))
    end
    sz = [h["image width"], h["image height"], h["frames per stack"], h["nStacks"]]
    kinds = ["space", "space", "space", "time"]
    if sz[end] == 1
        sz = sz[1:3]
        kinds = kinds[[1,2,4]]
    end
    println(sheader, "dimension: ", length(sz))
    print(sheader, "sizes:")
    for z in sz
        print(sheader, " ", z)
    end
    print(sheader, "\nkinds:")
    for k in kinds
        print(sheader, " ", k)
    end
    print(sheader, "\n")
    println(sheader, "encoding: raw")
    println(sheader, "endian: ", nrrd_endian_dict[h["byte order"]])
    if isa(datafilename, AbstractString)
        println(sheader, "data file: ", datafilename)
    end
    sheader
end

function imagine2nrrd(nrrdname::AbstractString, h::Dict{ASCIIString, Any}, datafilename = nothing)
    sheader = open(nrrdname, "w")
    imagine2nrrd(sheader, h, datafilename)
    close(sheader)
end

"""
`save_header(filename, header)` writes a header dictionary in Imagine format.

`save_header(destname, srcname, img::AbstractArray, [T::Type =
eltype(img)])` writes a `.imagine` file with name `destname`, using
the `.imagine` file `srcname` as a template. Size and element type
fields are updated from `img` and `T`, respectively.
"""
function save_header(filename::AbstractString, h::Dict{ASCIIString, Any})
    open(filename, "w") do io
        write(io, magic(format"Imagine"))
        println(io, "\n[general]")
        writekv(io, h, ("header version", "app version", "date and time", "byte order", "rig"))
        println(io, "\n[misc params]")
        writekv(io, h, ("stimulus file content", "comment", "ai data file","image data file", "piezo"))
        println(io, "\n[ai]")
        writekv(io, h, ("nscans", "channel list", "label list", "scan rate", "min sample", "max sample", "min input", "max input"))
        println(io, "\n[camera]")
        writekv(io, h, ("original image depth", "saved image depth", "image width", "image height", "number of frames requested", "nStacks", "idle time between stacks", "pre amp gain", "gain", "exposure time", "vertical shift speed", "vertical clock vol amp", "readout rate", "pixel order", "frame index offset", "frames per stack", "pixel data type", "camera", "um per pixel", "binning", "angle from horizontal (deg)"))
    end
    nothing
end

function save_header(dest::AbstractString, src::AbstractString, img::AbstractArray, T::Type = eltype(img))
    h = parse_header(src)
    fillsize!(h, img)
    h["pixel data type"] = lowercase(string(T))
    h["byte order"] = ENDIAN_BOM == 0x04030201 ? "l" : "b"
    save_header(dest, h)
end

function fillsize!(h, img::AbstractImage)
    h["image width"] = size(img,"x")
    h["image height"] = size(img,"l")
    h["frames per stack"] = size(img,"z")
    h["nStacks"] = size(img,"t")
    h
end

function fillsize!{T}(h, img::AbstractArray{T,4})
    h["image width"] = size(img,1)
    h["image height"] = size(img,2)
    h["frames per stack"] = size(img,3)
    h["nStacks"] = size(img,4)
    h
end

function writekv(io, h, fieldnames)
    for fn in fieldnames
        if haskey(h, fn)
            writefield(io, fn, h[fn])
        end
    end
end
writefield(io, fn, v) = println(io, fn, "=", v)
function writefield(io, fn, v::Number)
    print(io, fn, "=")
    if haskey(write_dict, fn)
        write_dict[fn](io, v)
    else
        println(io, isnan(v) ? "" : v)
    end
end
writefield(io, fn, v::AbstractVector) = println(io, fn, "=", join(map(string,v)," "))

function writefield(io, fn, dct::Dict)
    print(io, fn, "=")
    ks = collect(keys(dct))
    vs = collect(values(dct))
    for i = 1:length(ks)
        k, v = ks[i], vs[i]
        print(io, k, ':')
        if haskey(write_dict, k)
            write_dict[k](io, v)
        else
            print(io, v)
        end
        print(io, i == length(ks) ? '\n' : ';')
    end
end

writeum(io,x) = print(io, round(Int, 10^6*(x/Meter)), " um")
writeus(io,x::SIUnits.SIQuantity) = print(io, round(Int, 10^6*(x/Second)), " us")
writeus(io,x) = isnan(x) || print(io, round(Int, 10^6*(x/Second)), " us")
writeMHz(io,x::SIUnits.SIQuantity) = print(io, round(Int, 1e-6*(x*Second)), " MHz")
writeMHz(io,x) = isnan(x) || print(io, round(Int, 1e-6*(x*Second)), " MHz")
const write_dict = Dict{ASCIIString,Function}(
    "bidirection"                  => (io,x)->x ? print(io, 1) : print(io, 0),
    "start position"               => writeum,
    "stop position"                => writeum,
    "vertical shift speed"         => (io,x)->(writeus(io,x); print(io,'\n')),
    "readout rate"                 => (io,x)->(writeMHz(io,x); print(io,'\n')),
)

function __init__()
    Base.rehash!(nrrd_endian_dict)
end

end
