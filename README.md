# Introduction

This project is a GPU path tracer based on SDFs (signed distance fields) written using OpenGL and the zig programming languange. The path tracer itself is based on the cook-torrance microfacet BRDF, while zig is used to provide some sort o control over what would be more *game engine like* ideas. 


# Build
`zig build`

# Notes
There's a known problem that causes displacement maps on the SDFs to perform poorly on nvidia GPUs, currently unsure as to why.
