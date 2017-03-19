/++
$(H2 GLAS API)

Copyright: Copyright © 2016-, Ilya Yaroshenko.
License: $(HTTP boost.org/LICENSE_1_0.txt, Boost License 1.0).
Authors: Ilya Yaroshenko

$(H4 Transposition)
GLAS does not require transposition parameters.
Use $(LINK2 http://dlang.org/phobos/std_experimental_ndslice_iteration.html#transposed, transposed)
to perform zero cost ndslice transposition.

Note: $(LINK2 , ndslice) uses is row major representation.
    $(BR)
+/
module glas.ndslice;

version(D_Ddoc)
{
    enum SliceKind
    {
        universal,
        canonical,
        contiguous,
    }
    struct Structure(size_t N) {}
    struct Slice(SliceKind kind, size_t[] packs, Iterator) {}
}
else
{
    import mir.ndslice.slice: Slice, SliceKind, Structure;
}

extern(C) nothrow @nogc @system:

/++
Specifies if the matrix `asl` stores conjugated elements.
+/
enum ulong ConjA = 0x1;
/++
Specifies if the matrix `bsl` stores conjugated elements.
+/
enum ulong ConjB = 0x2;
/++
Specifies if the lower  triangular
part of the symmetric matrix A is to be referenced.

The lower triangular part of the matrix `asl`
must contain the lower triangular part of the symmetric / hermitian
matrix A and the strictly upper triangular part of `asl` is not
referenced.

Note: Lower is default flag.
+/
enum ulong Lower = 0x0;
/++
Specifies if the upper  triangular
part of the symmetric matrix A is to be referenced.

The upper triangular
part of the matrix `asl`  must contain the upper triangular part
of the symmetric / hermitian matrix A and the strictly lower triangular
part of `asl` is not referenced.
+/
enum ulong Upper = 0x0100;
/++
Specifies if the symmetric/hermitian matrix A
    appears on the left in the  operation.

Note: Left is default flag.
+/
enum ulong Left = 0x0;
/++
Specifies if the symmetric/hermitian matrix A
    appears on the left in the  operation.
+/
enum ulong Right = 0x0200;

/++
Params:
    error_code = Error code
Returns:
    error message
+/
string glas_error(int error_code);

/++
Validates input data for GEMM operations.
Params:
    as = structure for matrix A
    bs = structure for matrix B
    cs = structure for matrix C
    settings = Operation settings. Allowed flags are
            $(LREF ConjA), $(LREF ConjB).
Returns: 0 on success and error code otherwise.
+/
int glas_validate_gemm(Structure!2 as, Structure!2 bs, Structure!2 cs, ulong settings = 0);
/// ditto
alias validate_gemm = glas_validate_gemm;

/++
Validates input data for SYMM operations.
Params:
    as = structure for matrix A
    bs = structure for matrix B
    cs = structure for matrix C
    settings = Operation settings. Allowed flags are
            $(LREF Left), $(LREF Right),
            $(LREF Lower), $(LREF Upper),
            $(LREF ConjA), $(LREF ConjB).
            $(LREF ConjA) flag specifies if the matrix A is hermitian.
Returns: 0 on success and error code otherwise.
+/
int glas_validate_symm(Structure!2 as, Structure!2 bs, Structure!2 cs, ulong settings = 0);
/// ditto
alias validate_symm = glas_validate_symm;

/++
Performs general matrix-matrix multiplication.

Pseudo_code: `C := alpha A × B + beta C`.

Params:
    alpha = scalar
    asl = `m ⨉ k` matrix
    bsl = `k ⨉ n` matrix
    beta = scalar. When  `beta`  is supplied as zero then the matrix `csl` need not be set on input.
    csl = `m ⨉ n` matrix with one stride equal to `±1`.
    settings = Operation settings. Allowed flags are $(LREF ConjA) and $(LREF ConjB).

Unified_alias: `gemm`

BLAS: SGEMM, DGEMM, CGEMM, ZGEMM
+/
void glas_sgemm(float alpha, Slice!(SliceKind.universal, [2], const(float)*) asl, Slice!(SliceKind.universal, [2], const(float)*) bsl, float beta, Slice!(SliceKind.universal, [2], float*) csl, ulong settings = 0);
/// ditto
void glas_dgemm(double alpha, Slice!(SliceKind.universal, [2], const(double)*) asl, Slice!(SliceKind.universal, [2], const(double)*) bsl, double beta, Slice!(SliceKind.universal, [2], double*) csl, ulong settings = 0);
/// ditto
void glas_cgemm(cfloat alpha, Slice!(SliceKind.universal, [2], const(cfloat)*) asl, Slice!(SliceKind.universal, [2], const(cfloat)*) bsl, cfloat beta, Slice!(SliceKind.universal, [2], cfloat*) csl, ulong settings = 0);
/// ditto
void glas_zgemm(cdouble alpha, Slice!(SliceKind.universal, [2], const(cdouble)*) asl, Slice!(SliceKind.universal, [2], const(cdouble)*) bsl, cdouble beta, Slice!(SliceKind.universal, [2], cdouble*) csl, ulong settings = 0);

/// ditto
alias gemm = glas_sgemm;
/// ditto
alias gemm = glas_dgemm;
/// ditto
alias gemm = glas_cgemm;
/// ditto
alias gemm = glas_zgemm;

/++
Performs symmetric or hermitian matrix-matrix multiplication.

Pseudo_code: `C := alpha A × B + beta C` or `C := alpha B × A + beta C`,
    where  `alpha` and `beta` are scalars, `A` is a symmetric or hermitian matrix and `B` and
    `C` are `m × n` matrices.

Params:
    alpha = scalar
    asl = `k ⨉ k` matrix, where `k` is `n`  when $(LREF Right) flag is set
           and is `m` otherwise.
    bsl = `m ⨉ n` matrix
    beta = scalar. When  `beta`  is supplied as zero then the matrix `csl` need not be set on input.
    csl = `m ⨉ n` matrix with one stride equals to `±1`.
    settings = Operation settings.
        Allowed flags are
            $(LREF Left), $(LREF Right),
            $(LREF Lower), $(LREF Upper),
            $(LREF ConjA), $(LREF ConjB).
            $(LREF ConjA) flag specifies if the matrix A is hermitian.

Unified_alias: `symm`

BLAS: SSYMM, DSYMM, CSYMM, ZSYMM, SHEMM, DHEMM, CHEMM, ZHEMM
+/
void glas_ssymm(float alpha, Slice!(SliceKind.universal, [2], const(float)*) asl, Slice!(SliceKind.universal, [2], const(float)*) bsl, float beta, Slice!(SliceKind.universal, [2], float*) csl, ulong settings = 0);
/// ditto
void glas_dsymm(double alpha, Slice!(SliceKind.universal, [2], const(double)*) asl, Slice!(SliceKind.universal, [2], const(double)*) bsl, double beta, Slice!(SliceKind.universal, [2], double*) csl, ulong settings = 0);
/// ditto
void glas_csymm(cfloat alpha, Slice!(SliceKind.universal, [2], const(cfloat)*) asl, Slice!(SliceKind.universal, [2], const(cfloat)*) bsl, cfloat beta, Slice!(SliceKind.universal, [2], cfloat*) csl, ulong settings = 0);
/// ditto
void glas_zsymm(cdouble alpha, Slice!(SliceKind.universal, [2], const(cdouble)*) asl, Slice!(SliceKind.universal, [2], const(cdouble)*) bsl, cdouble beta, Slice!(SliceKind.universal, [2], cdouble*) csl, ulong settings = 0);

/// ditto
alias symm = glas_ssymm;
/// ditto
alias symm = glas_dsymm;
/// ditto
alias symm = glas_csymm;
/// ditto
alias symm = glas_zsymm;

pure:

/++
`copy` copies a vector, `x`, to a vector, `y`.

Pseudo_code: `y := x`.

Unified_alias: `copy`

BLAS: SCOPY, DCOPY, CCOPY, ZCOPY
+/
void glas_scopy(Slice!(SliceKind.universal, [1], const(float)*) xsl, Slice!(SliceKind.universal, [1], float*) ysl);
/// ditto
void glas_dcopy(Slice!(SliceKind.universal, [1], const(double)*) xsl, Slice!(SliceKind.universal, [1], double*) ysl);
/// ditto
void glas_ccopy(Slice!(SliceKind.universal, [1], const(cfloat)*) xsl, Slice!(SliceKind.universal, [1], float*) ysl);
/// ditto
void glas_zcopy(Slice!(SliceKind.universal, [1], const(cdouble)*) xsl, Slice!(SliceKind.universal, [1], cdouble*) ysl);

/// ditto
void _glas_scopy(size_t n, ptrdiff_t incx, const(float)* x, ptrdiff_t incy, float* y);
/// ditto
void _glas_dcopy(size_t n, ptrdiff_t incx, const(double)* x, ptrdiff_t incy, double* y);
/// ditto
void _glas_ccopy(size_t n, ptrdiff_t incx, const(cfloat)* x, ptrdiff_t incy, cfloat* y);
/// ditto
void _glas_zcopy(size_t n, ptrdiff_t incx, const(cdouble)* x, ptrdiff_t incy, cdouble* y);

/// ditto
alias copy = glas_scopy;
/// ditto
alias copy = glas_dcopy;
/// ditto
alias copy = glas_ccopy;
/// ditto
alias copy = glas_zcopy;

/// ditto
alias copy = _glas_scopy;
/// ditto
alias copy = _glas_dcopy;
/// ditto
alias copy = _glas_ccopy;
/// ditto
alias copy = _glas_zcopy;

/++
`swap` interchanges two vectors.

Pseudo_code: `x <-> y`.

Unified_alias: `swap`

BLAS: SSWAP, DSWAP, CSWAP, ZSWAP
+/
void glas_sswap(Slice!(SliceKind.universal, [1], float*) xsl, Slice!(SliceKind.universal, [1], float*) ysl);
/// ditto
void glas_dswap(Slice!(SliceKind.universal, [1], double*) xsl, Slice!(SliceKind.universal, [1], double*) ysl);
/// ditto
void glas_cswap(Slice!(SliceKind.universal, [1], cfloat*) xsl, Slice!(SliceKind.universal, [1], float*) ysl);
/// ditto
void glas_zswap(Slice!(SliceKind.universal, [1], cdouble*) xsl, Slice!(SliceKind.universal, [1], cdouble*) ysl);

/// ditto
void _glas_sswap(size_t n, ptrdiff_t incx, float* x, ptrdiff_t incy, float* y);
/// ditto
void _glas_dswap(size_t n, ptrdiff_t incx, double* x, ptrdiff_t incy, double* y);
/// ditto
void _glas_cswap(size_t n, ptrdiff_t incx, cfloat* x, ptrdiff_t incy, cfloat* y);
/// ditto
void _glas_zswap(size_t n, ptrdiff_t incx, cdouble* x, ptrdiff_t incy, cdouble* y);

/// ditto
alias swap = glas_sswap;
/// ditto
alias swap = glas_dswap;
/// ditto
alias swap = glas_cswap;
/// ditto
alias swap = glas_zswap;

/// ditto
alias swap = _glas_sswap;
/// ditto
alias swap = _glas_dswap;
/// ditto
alias swap = _glas_cswap;
/// ditto
alias swap = _glas_zswap;

/++
Constant times a vector plus a vector.

Pseudo_code: `y += a * x`.

Unified_alias: `axpy`

BLAS: SAXPY, DAXPY, CAXPY, ZAXPY
+/
void glas_saxpy(float a, Slice!(SliceKind.universal, [1], const(float)*) xsl, Slice!(SliceKind.universal, [1], float*) ysl);
/// ditto
void glas_daxpy(double a, Slice!(SliceKind.universal, [1], const(double)*) xsl, Slice!(SliceKind.universal, [1], double*) ysl);
/// ditto
void glas_caxpy(cfloat a, Slice!(SliceKind.universal, [1], const(cfloat)*) xsl, Slice!(SliceKind.universal, [1], float*) ysl);
/// ditto
void glas_zaxpy(cdouble a, Slice!(SliceKind.universal, [1], const(cdouble)*) xsl, Slice!(SliceKind.universal, [1], cdouble*) ysl);

/// ditto
void _glas_saxpy(float a, size_t n, ptrdiff_t incx, const(float)* x, ptrdiff_t incy, float* y);
/// ditto
void _glas_daxpy(double a, size_t n, ptrdiff_t incx, const(double)* x, ptrdiff_t incy, double* y);
/// ditto
void _glas_caxpy(cfloat a, size_t n, ptrdiff_t incx, const(cfloat)* x, ptrdiff_t incy, cfloat* y);
/// ditto
void _glas_zaxpy(cdouble a, size_t n, ptrdiff_t incx, const(cdouble)* x, ptrdiff_t incy, cdouble* y);

/// ditto
alias axpy = glas_saxpy;
/// ditto
alias axpy = glas_daxpy;
/// ditto
alias axpy = glas_caxpy;
/// ditto
alias axpy = glas_zaxpy;

/// ditto
alias axpy = _glas_saxpy;
/// ditto
alias axpy = _glas_daxpy;
/// ditto
alias axpy = _glas_caxpy;
/// ditto
alias axpy = _glas_zaxpy;

/++
`scal` scales a vector by a constant.

Pseudo_code: `x := a x`.

Unified_alias: `scal`

BLAS: SSSCAL, DSSCAL, CSSCAL, ZSSCAL, CSCAL, ZSCAL
+/
void glas_sscal(float a, Slice!(SliceKind.universal, [1], float*) xsl);
/// ditto
void glas_dscal(double a, Slice!(SliceKind.universal, [1], double*) xsl);
/// ditto
void glas_csscal(float a, Slice!(SliceKind.universal, [1], cfloat*) xsl);
/// ditto
void glas_cscal(cfloat a, Slice!(SliceKind.universal, [1], cfloat*) xsl);
/// ditto
void glas_csIscal(ifloat a, Slice!(SliceKind.universal, [1], cfloat*) xsl);
/// ditto
void glas_zdscal(double a, Slice!(SliceKind.universal, [1], cdouble*) xsl);
/// ditto
void glas_zscal(cdouble a, Slice!(SliceKind.universal, [1], cdouble*) xsl);
/// ditto
void glas_zdIscal(idouble a, Slice!(SliceKind.universal, [1], cdouble*) xsl);

/// ditto
void _glas_sscal(float a, size_t n, ptrdiff_t incx, float* x);
/// ditto
void _glas_dscal(double a, size_t n, ptrdiff_t incx, double* x);
/// ditto
void _glas_csscal(float a, size_t n, ptrdiff_t incx, cfloat* x);
/// ditto
void _glas_cscal(cfloat a, size_t n, ptrdiff_t incx, cfloat* x);
/// ditto
void _glas_csIscal(ifloat a, size_t n, ptrdiff_t incx, cfloat* x);
/// ditto
void _glas_zdscal(double a, size_t n, ptrdiff_t incx, cdouble* x);
/// ditto
void _glas_zscal(cdouble a, size_t n, ptrdiff_t incx, cdouble* x);
/// ditto
void _glas_zdIscal(idouble a, size_t n, ptrdiff_t incx, cdouble* x);

/// ditto
alias scal = glas_sscal;
/// ditto
alias scal = glas_dscal;
/// ditto
alias scal = glas_csscal;
/// ditto
alias scal = glas_cscal;
/// ditto
alias scal = glas_csIscal;
/// ditto
alias scal = glas_zdscal;
/// ditto
alias scal = glas_zscal;
/// ditto
alias scal = glas_zdIscal;

/// ditto
alias scal = _glas_sscal;
/// ditto
alias scal = _glas_dscal;
/// ditto
alias scal = _glas_csscal;
/// ditto
alias scal = _glas_cscal;
/// ditto
alias scal = _glas_csIscal;
/// ditto
alias scal = _glas_zdscal;
/// ditto
alias scal = _glas_zscal;
/// ditto
alias scal = _glas_zdIscal;
