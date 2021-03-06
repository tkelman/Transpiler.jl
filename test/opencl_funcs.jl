using Transpiler
using Base.Test
import Transpiler.CLTranspiler: cli, CLMethod
using Sugar: getsource!, dependencies!

function test{T}(a::T, b)
    x = sqrt(sin(a) * b) / T(10.0)
    y = T(33.0)x + cos(b)
    y * T(10.0)
end

function mapkernel(f, a, b, c)
    gid = cli.get_global_id(0) + 1
    c[gid] = f(a[gid], b[gid])
    return
end

# empty caches
Transpiler.empty_caches!()

args = (typeof(+), cli.CLArray{Float32, 1}, cli.CLArray{Float32, 1}, cli.CLArray{Float32, 1})
cl_mapkernel = CLMethod((mapkernel, args))
source = getsource!(cl_mapkernel)
mapsource = """void mapkernel_1(Base123 f, __global float * restrict  a, __global float * restrict  b, __global float * restrict  c)
{
    int gid;
    gid = get_global_id(0) + 1;
    float _ssavalue_0;
    _ssavalue_0 = a[gid - 1] + b[gid - 1];
    c[gid - 1] = _ssavalue_0;
    ;
}"""

@testset "map kernel" begin
    @test source == mapsource
    deps = dependencies!(cl_mapkernel, true)
    @test length(deps) == 8
    deps_test = [
        Int64,
        (+, Tuple{Int64,Int64}),
        (cli.get_global_id, Tuple{Int64}),
        (+, Tuple{Float32, Float32}),
        Float32,
        (-, Tuple{Int64,Int64}),
        typeof(+),
        cli.CLArray{Float32,1}
    ]
    for elem in deps
        @test elem.signature in deps_test
    end
end

#Broadcast
Base.@propagate_inbounds broadcast_index(arg, shape, i) = arg
Base.@propagate_inbounds function broadcast_index{T, N}(
        arg::AbstractArray{T, N}, shape::NTuple{N, Integer}, i
    )
    @inbounds return arg[i]
end

# The implementation of prod in base doesn't play very well with current
# transpiler. TODO figure out what Core._apply maps to!
_prod{T}(x::NTuple{1, T}) = x[1]
_prod{T}(x::NTuple{2, T}) = x[1] * x[2]

function broadcast_kernel(A, f, sz, arg1, arg2)
    i = cli.get_global_id(0) + 1
    @inbounds if i <= _prod(sz)
        A[i] = f(
            broadcast_index(arg1, sz, i),
            broadcast_index(arg2, sz, i),
        )
    end
    return
end

args = (cli.CLArray{Float32, 1}, typeof(+), Tuple{Int32}, cli.CLArray{Float32, 1}, Float32)
cl_mapkernel = CLMethod((broadcast_kernel, args))
source = getsource!(cl_mapkernel)
broadcastsource = """void broadcast_kernel_5(__global float * restrict  A, Base123 f, int sz, __global float * restrict  arg1, float arg2)
{
    int i;
    i = get_global_id(0) + 1;
    ;
    if(i <= _prod_2(sz)){
        float _ssavalue_0;
        _ssavalue_0 = broadcast_index_3(arg1, sz, i) + broadcast_index_4(arg2, sz, i);
        A[i - 1] = _ssavalue_0;
    };
    ;
    ;
}"""

@testset "broadcast kernel" begin
    @test source == broadcastsource
    deps = dependencies!(cl_mapkernel, true)
    @test length(deps) == 13
    deps_test = [
        Int64,
        (+,Tuple{Int64,Int64}),
        (cli.get_global_id,Tuple{Int64}),
        (<=,Tuple{Int64,Int32}),
        (_prod,Tuple{Tuple{Int32}}),
        (+,Tuple{Float32,Float32}),
        (broadcast_index,Tuple{cli.CLArray{Float32,1},Tuple{Int32},Int64}),
        (broadcast_index,Tuple{Float32,Tuple{Int32},Int64}),
        (-,Tuple{Int64,Int64}),
        cli.CLArray{Float32,1},
        typeof(+),
        Tuple{Int32},
        Float32
    ]
    for elem in deps
        @test elem.signature in deps_test
    end
end
