_jl_sparse_lusolve{T1,T2}(S::SparseMatrixCSC{T1}, b::Vector{T2}) = S \ convert(Array{T1,1}, b)

function _jl_sparse_lusolve{Tv<:Union(Float64,Complex128), Ti<:Union(Int64,Int32)}(S::SparseMatrixCSC{Tv,Ti}, b::Vector{Tv})

    S = _jl_convert_to_0_based_indexing!(S)
    x = []

    try
        symbolic = _jl_umfpack_symbolic(S)
        numeric = _jl_umfpack_numeric(S, symbolic)
        _jl_umfpack_free_symbolic(S, symbolic)
        x = _jl_umfpack_solve(S, b, numeric)
        _jl_umfpack_free_numeric(S, numeric)
    catch
        S = _jl_convert_to_1_based_indexing!(S)
        error("Error calling UMFPACK")
    end
    
    S = _jl_convert_to_1_based_indexing!(S)
    return x
end


function (\)(A, b) 
    return _jl_sparse_lusolve(A, b)
end

function _jl_cholmod_transpose(S::SparseMatrixCSC)
    cm = Array(Ptr{Void}, 1)
    _jl_cholmod_start(cm)
    S = _jl_convert_to_0_based_indexing!(S)
    cs = _jl_cholmod_sparse(S)
    cs_T = _jl_cholmod_transpose(cs, cm)
    S = _jl_convert_to_1_based_indexing!(S)
    return cs_T
end

## Library code

_jl_libsuitesparse = dlopen("libsuitesparse")
_jl_libsuitesparse_wrapper = dlopen("libsuitesparse_wrapper")

## CHOLMOD

# itype defines the types of integer used:
const _jl_CHOLMOD_INT  = int32(0)  # all integer arrays are int 
const _jl_CHOLMOD_LONG = int32(2)  # all integer arrays are UF_long 

# dtype defines what the numerical type is (double or float):
const _jl_CHOLMOD_DOUBLE = int32(0)        # all numerical values are double 
const _jl_CHOLMOD_SINGLE = int32(1)        # all numerical values are float 

# xtype defines the kind of numerical values used:
const _jl_CHOLMOD_PATTERN = int32(0)       # pattern only, no numerical values 
const _jl_CHOLMOD_REAL    = int32(1)       # a real matrix 
const _jl_CHOLMOD_COMPLEX = int32(2)       # a complex matrix (ANSI C99 compatible) 
const _jl_CHOLMOD_ZOMPLEX = int32(3)       # a complex matrix (MATLAB compatible) 

# Definitions for cholmod_common: 
const _jl_CHOLMOD_MAXMETHODS = int32(9)    # maximum number of different methods that 
                                    # cholmod_analyze can try. Must be >= 9. 

# Common->status values.  zero means success, negative means a fatal error, positive is a warning. 
const _jl_CHOLMOD_OK            = int32(0)    # success 
const _jl_CHOLMOD_NOT_INSTALLED = int32(-1)   # failure: method not installed 
const _jl_CHOLMOD_OUT_OF_MEMORY = int32(-2)   # failure: out of memory 
const _jl_CHOLMOD_TOO_LARGE     = int32(-3)   # failure: integer overflow occured 
const _jl_CHOLMOD_INVALID       = int32(-4)   # failure: invalid input 
const _jl_CHOLMOD_NOT_POSDEF    = int32(1)    # warning: matrix not pos. def. 
const _jl_CHOLMOD_DSMALL        = int32(2)    # warning: D for LDL'  or diag(L) or LL' has tiny absolute value 

# ordering method (also used for L->ordering) 
const _jl_CHOLMOD_NATURAL = int32(0)     # use natural ordering 
const _jl_CHOLMOD_GIVEN   = int32(1)     # use given permutation 
const _jl_CHOLMOD_AMD     = int32(2)     # use minimum degree (AMD) 
const _jl_CHOLMOD_METIS   = int32(3)     # use METIS' nested dissection 
const _jl_CHOLMOD_NESDIS  = int32(4)     # use _jl_CHOLMOD's version of nested dissection:
                                         # node bisector applied recursively, followed
                                         # by constrained minimum degree (CSYMAMD or CCOLAMD) 
const _jl_CHOLMOD_COLAMD  = int32(5)     # use AMD for A, COLAMD for A*A' 

# POSTORDERED is not a method, but a result of natural ordering followed by a
# weighted postorder.  It is used for L->ordering, not method [ ].ordering. 
const _jl_CHOLMOD_POSTORDERED  = int32(6)   # natural ordering, postordered. 

# supernodal strategy (for Common->supernodal) 
const _jl_CHOLMOD_SIMPLICIAL = int32(0)    # always do simplicial 
const _jl_CHOLMOD_AUTO       = int32(1)    # select simpl/super depending on matrix 
const _jl_CHOLMOD_SUPERNODAL = int32(2)    # always do supernodal 

## CHOLMOD functions

function _jl_cholmod_start(cm)
    ccall(dlsym(_jl_libsuitesparse, :cholmod_start),
          Void,
          (Ptr{Void}, ),
          cm);
    return
end

## Call wrapper function to create cholmod_sparse objects
## Assumes that S has been converted to 0-based indexing in caller
function _jl_cholmod_sparse{Tv,Ti}(S::SparseMatrixCSC{Tv,Ti})
    if     Ti == Int32; itype = _jl_CHOLMOD_INT;
    elseif Ti == Int64; itype = _jl_CHOLMOD_LONG; end

    if     Tv == Float64    || Tv == Float32;    xtype = _jl_CHOLMOD_REAL;
    elseif Tv == Complex128 || Tv == Complex64 ; xtype = _jl_CHOLMOD_COMPLEX; end

    if     Tv == Float64 || Tv == Complex128; dtype = _jl_CHOLMOD_DOUBLE; 
    elseif Tv == Float32 || Tv == Complex64 ; dtype = _jl_CHOLMOD_SINGLE; end

    cs = ccall(dlsym(_jl_libsuitesparse_wrapper, :jl_cholmod_sparse),
               Ptr{Void},
               (Int, Int, Ptr{Void}, Ptr{Void}, Ptr{Void}, Ptr{Void}, Ptr{Void}, 
                Int32, Int32, Int32, Int32, Int32),
               int(S.m), int(S.n), S.colptr, S.rowval, C_NULL, S.nzval, C_NULL,
               itype, xtype, dtype, int32(1), int32(1)
               )

    return cs
end

function _jl_cholmod_transpose(cs::Ptr{Void}, cm::Ptr{Void})
    t = ccall(dlsym(_jl_libsuitesparse, :cholmod_transpose),
              Ptr{Void},
              (Ptr{Void}, Int32, Ptr{Void}),
              cs, 2, cm);
    return t
end

## UMFPACK

## Type of solve
const _jl_UMFPACK_A     =  0     # Ax=b
const _jl_UMFPACK_At    =  1     # A'x=b
const _jl_UMFPACK_Aat   =  2     # A.'x=b
const _jl_UMFPACK_Pt_L  =  3     # P'Lx=b
const _jl_UMFPACK_L     =  4     # Lx=b
const _jl_UMFPACK_Lt_P  =  5     # L'Px=b
const _jl_UMFPACK_Lat_P =  6     # L.'Px=b
const _jl_UMFPACK_Lt    =  7     # L'x=b
const _jl_UMFPACK_Lat   =  8     # L.'x=b
const _jl_UMFPACK_U_Qt  =  9     # UQ'x=b
const _jl_UMFPACK_U     =  10    # Ux=b
const _jl_UMFPACK_Q_Ut  =  11    # QU'x=b
const _jl_UMFPACK_Q_Uat =  12    # QU.'x=b
const _jl_UMFPACK_Ut    =  13    # U'x=b
const _jl_UMFPACK_Uat   =  14    # U.'x=b

## Sizes of Control and Info arrays for returning information from solver
const _jl_UMFPACK_INFO = 90
const _jl_UMFPACK_CONTROL = 20

## Status codes
const _jl_UMFPACK_OK = 0
const _jl_UMFPACK_WARNING_singular_matrix       = 1
const _jl_UMFPACK_WARNING_determinant_underflow = 2
const _jl_UMFPACK_WARNING_determinant_overflow  = 3
const _jl_UMFPACK_ERROR_out_of_memory           = -1
const _jl_UMFPACK_ERROR_invalid_Numeric_object  = -3
const _jl_UMFPACK_ERROR_invalid_Symbolic_object = -4
const _jl_UMFPACK_ERROR_argument_missing        = -5
const _jl_UMFPACK_ERROR_n_nonpositive           = -6
const _jl_UMFPACK_ERROR_invalid_matrix          = -8
const _jl_UMFPACK_ERROR_different_pattern       = -11
const _jl_UMFPACK_ERROR_invalid_system          = -13
const _jl_UMFPACK_ERROR_invalid_permutation     = -15
const _jl_UMFPACK_ERROR_internal_error          = -911
const _jl_UMFPACK_ERROR_file_IO                 = -17
const _jl_UMFPACK_ERROR_ordering_failed         = -18

## UMFPACK works with 0 based indexing
function _jl_convert_to_0_based_indexing!(S::SparseMatrixCSC)
    for i=1:(S.colptr[end]-1); S.rowval[i] -= 1; end
    for i=1:length(S.colptr); S.colptr[i] -= 1; end
    return S
end

function _jl_convert_to_1_based_indexing!(S::SparseMatrixCSC)
    for i=1:length(S.colptr); S.colptr[i] += 1; end
    for i=1:(S.colptr[end]-1); S.rowval[i] += 1; end
    return S
end

## Wrappers around UMFPACK routines

macro _jl_umfpack_symbolic_macro(f_sym_r, f_sym_c, inttype)
    quote

        function _jl_umfpack_symbolic{Tv<:Float64,Ti<:$inttype}(S::SparseMatrixCSC{Tv,Ti})
            # Pointer to store the symbolic factorization returned by UMFPACK
            Symbolic = Array(Ptr{Void}, 1)
            status = ccall(dlsym(_jl_libsuitesparse, $f_sym_r),
                           Ti,
                           (Ti, Ti, 
                            Ptr{Ti}, Ptr{Ti}, Ptr{Float64}, Ptr{Void}, Ptr{Float64}, Ptr{Float64}),
                           convert($inttype, S.m), convert($inttype, S.n), 
                           S.colptr, S.rowval, S.nzval, Symbolic, C_NULL, C_NULL)
            if status != _jl_UMFPACK_OK; error("Error in symoblic factorization"); end
            return Symbolic
        end

        function _jl_umfpack_symbolic{Tv<:Complex128,Ti<:$inttype}(S::SparseMatrixCSC{Tv,Ti})
            # Pointer to store the symbolic factorization returned by UMFPACK
            Symbolic = Array(Ptr{Void}, 1)            
            status = ccall(dlsym(_jl_libsuitesparse, $f_sym_c),
                           Ti,
                           (Ti, Ti, 
                            Ptr{Ti}, Ptr{Ti}, Ptr{Float64}, Ptr{Float64}, Ptr{Void}, 
                            Ptr{Float64}, Ptr{Float64}),
                           convert($inttype, S.m), convert($inttype, S.n), 
                           S.colptr, S.rowval, real(S.nzval), imag(S.nzval), Symbolic, 
                           C_NULL, C_NULL)
            if status != _jl_UMFPACK_OK; error("Error in symoblic factorization"); end
            return Symbolic
        end

    end
end

@_jl_umfpack_symbolic_macro :umfpack_di_symbolic :umfpack_zi_symbolic Int32
@_jl_umfpack_symbolic_macro :umfpack_dl_symbolic :umfpack_zl_symbolic Int64

macro _jl_umfpack_numeric_macro(f_num_r, f_num_c, inttype)
    quote

        function _jl_umfpack_numeric{Tv<:Float64,Ti<:$inttype}(S::SparseMatrixCSC{Tv,Ti}, Symbolic)
            # Pointer to store the numeric factorization returned by UMFPACK
            Numeric = Array(Ptr{Void}, 1)
            status = ccall(dlsym(_jl_libsuitesparse, $f_num_r),
                           Ti,
                           (Ptr{Ti}, Ptr{Ti}, Ptr{Float64}, Ptr{Void}, Ptr{Void}, 
                            Ptr{Float64}, Ptr{Float64}),
                           S.colptr, S.rowval, S.nzval, Symbolic[1], Numeric, 
                           C_NULL, C_NULL)
            if status != _jl_UMFPACK_OK; error("Error in numeric factorization"); end
            return Numeric
        end

        function _jl_umfpack_numeric{Tv<:Complex128,Ti<:$inttype}(S::SparseMatrixCSC{Tv,Ti}, Symbolic)
            # Pointer to store the numeric factorization returned by UMFPACK
            Numeric = Array(Ptr{Void}, 1)
            status = ccall(dlsym(_jl_libsuitesparse, $f_num_c),
                           Ti,
                           (Ptr{Ti}, Ptr{Ti}, Ptr{Float64}, Ptr{Float64}, Ptr{Void}, Ptr{Void}, 
                            Ptr{Float64}, Ptr{Float64}),
                           S.colptr, S.rowval, real(S.nzval), imag(S.nzval), Symbolic[1], Numeric, 
                           C_NULL, C_NULL)
            if status != _jl_UMFPACK_OK; error("Error in numeric factorization"); end
            return Numeric
        end

    end
end

@_jl_umfpack_numeric_macro :umfpack_di_numeric :umfpack_zi_numeric Int32
@_jl_umfpack_numeric_macro :umfpack_dl_numeric :umfpack_zl_numeric Int64

macro _jl_umfpack_solve_macro(f_sol_r, f_sol_c, inttype)
    quote

        function _jl_umfpack_solve{Tv<:Float64,Ti<:$inttype}(S::SparseMatrixCSC{Tv,Ti}, 
                                                             b::Vector{Tv}, Numeric)
            x = similar(b)
            status = ccall(dlsym(_jl_libsuitesparse, $f_sol_r),
                           Ti,
                           (Ti, Ptr{Ti}, Ptr{Ti}, Ptr{Float64}, 
                            Ptr{Float64}, Ptr{Float64}, Ptr{Void}, Ptr{Float64}, Ptr{Float64}),
                           convert(Ti, _jl_UMFPACK_A), S.colptr, S.rowval, S.nzval, 
                           x, b, Numeric[1], C_NULL, C_NULL)
            if status != _jl_UMFPACK_OK; error("Error in solve"); end
            return x
        end

        function _jl_umfpack_solve{Tv<:Complex128,Ti<:$inttype}(S::SparseMatrixCSC{Tv,Ti}, 
                                                                b::Vector{Tv}, Numeric)
            xr = similar(b, Float64)
            xi = similar(b, Float64)
            status = ccall(dlsym(_jl_libsuitesparse, $f_sol_c),
                           Ti,
                           (Ti, Ptr{Ti}, Ptr{Ti}, Ptr{Float64}, Ptr{Float64}, Ptr{Float64}, Ptr{Float64}, 
                            Ptr{Float64}, Ptr{Float64}, Ptr{Void}, Ptr{Float64}, Ptr{Float64}),
                           convert(Ti, _jl_UMFPACK_A), S.colptr, S.rowval, real(S.nzval), imag(S.nzval), 
                           xr, xi, real(b), imag(b), Numeric[1], C_NULL, C_NULL)
            if status != _jl_UMFPACK_OK; error("Error in solve"); end
            return complex(xr,xi)
        end

    end
end

@_jl_umfpack_solve_macro :umfpack_di_solve :umfpack_zi_solve Int32
@_jl_umfpack_solve_macro :umfpack_dl_solve :umfpack_zl_solve Int64

macro _jl_umfpack_free_macro(f_symfree, f_numfree, eltype, inttype)
    quote

        _jl_umfpack_free_symbolic{Tv<:$eltype,Ti<:$inttype}(S::SparseMatrixCSC{Tv,Ti}, Symbolic) =
        ccall(dlsym(_jl_libsuitesparse, $f_symfree), Void, (Ptr{Void},), Symbolic)
        
        _jl_umfpack_free_numeric{Tv<:$eltype,Ti<:$inttype}(S::SparseMatrixCSC{Tv,Ti}, Numeric) =
        ccall(dlsym(_jl_libsuitesparse, $f_numfree), Void, (Ptr{Void},), Numeric)
        
    end
end

@_jl_umfpack_free_macro :umfpack_di_free_symbolic :umfpack_di_free_numeric Float64    Int32
@_jl_umfpack_free_macro :umfpack_zi_free_symbolic :umfpack_zi_free_numeric Complex128 Int32
@_jl_umfpack_free_macro :umfpack_dl_free_symbolic :umfpack_dl_free_numeric Float64    Int64
@_jl_umfpack_free_macro :umfpack_zl_free_symbolic :umfpack_zl_free_numeric Complex128 Int64

