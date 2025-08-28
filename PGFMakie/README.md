# PGFMakie

[![Build Status](https://github.com/jlbosse/PGFMakie.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/jlbosse/PGFMakie.jl/actions/workflows/CI.yml?query=branch%3Amain)

## Resources
MakieTex.jl to understand how to get tex strings to rasterized, Makie friendly images

## TODO
 - Everything

## Plan of attack
 - Copy over TEXDocument and CachedTEX from MakieTex.jl
 - Copy over everything needed to get `rasterize(::CachedTEX)` to work
 - Hook this up into `Makie.colorbuffer`
 - Maybe/hopefully get some constants to plot?
