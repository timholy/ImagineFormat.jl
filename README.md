# ImagineFormat

[![Build Status](https://travis-ci.org/timholy/ImagineFormat.jl.svg?branch=master)](https://travis-ci.org/timholy/ImagineFormat.jl)

Imagine is an acquisition program for light sheet microscopy written
by Zhongsheng Guo in Tim Holy's lab. This package implements a loader
for the file format for the Julia programming language. Each Imagine
"file" consists of two parts (as two separate files): a `*.imagine`
file which contains the (ASCII) header, and a `*.cam` file which
contains the camera data.  The `*.cam` file is a raw byte dump, and is
compatible with the NRRD "raw" file.

## Usage

Read Imagine files like this:
```jl
using Images
img = load("filename")
```
