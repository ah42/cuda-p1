/* This contains selected functions from CUDA SDK 4.0.17 */

#ifndef _CUDA_SAFECALLS_H
#define _CUDA_SAFECALLS_H

#include <stdio.h>

inline cudaError cutilDeviceSynchronize()
{
#if CUDART_VERSION >= 4000
        return cudaDeviceSynchronize();
#else
        return cudaThreadSynchronize();
#endif
}

inline cudaError cutilDeviceReset()
{
#if CUDART_VERSION >= 4000
        return cudaDeviceReset();
#else
        return cudaThreadExit();
#endif
}


// We define these calls here, so the user doesn't need to include __FILE__ and __LINE__
// The advantage is the developers gets to use the inline function so they can debug
#define cutilSafeCallNoSync(err)     __cudaSafeCallNoSync(err, __FILE__, __LINE__)
#define cutilSafeCall(err)           __cudaSafeCall      (err, __FILE__, __LINE__)
#define cutilSafeCall1(err,iter)     __cudaSafeCall1      (err, __FILE__, __LINE__,iter)
#define cutilSafeThreadSync()        __cudaSafeThreadSync(__FILE__, __LINE__)
#define cufftSafeCall(err)           __cufftSafeCall     (err, __FILE__, __LINE__)

// NOTE: "%s(%i) : " allows Visual Studio to directly jump to the file at the right line
// when the user double clicks on the error line in the Output pane. Like any compile error.

inline void __cudaSafeCallNoSync( cudaError err, const char *file, const int line ) {
	if( cudaSuccess != err) {
		fprintf(stderr, "%s(%i) : cudaSafeCallNoSync() Runtime API error %d : %s.\n",
				file, line, (int)err, cudaGetErrorString( err ) );
		exit(-1);
	}
}

inline void __cudaSafeCall( cudaError err, const char *file, const int line) {
	if( cudaSuccess != err) {
		fprintf(stderr, "%s(%i) : cudaSafeCall() Runtime API error %d: %s.\n",
				file, line, (int)err, cudaGetErrorString( err ));
		exit(-1);
	}
}

inline void __cudaSafeCall1( cudaError err, const char *file, const int line , int iter) {
	if( cudaSuccess != err) {
		fprintf(stderr, "%s(%i) : cudaSafeCall() Runtime API error %d: %s, iteration %d.\n",
				file, line, (int)err, cudaGetErrorString( err ) ,iter);
		exit(-1);
	}
}

inline void __cudaSafeThreadSync( const char *file, const int line ) {
	cudaError err = cutilDeviceSynchronize();
	if ( cudaSuccess != err) {
		fprintf(stderr, "%s(%i) : cudaDeviceSynchronize() Runtime API error %d: %s.\n",
				file, line, (int)err, cudaGetErrorString( err ) );
		exit(-1);
	}
}

#ifdef _CUFFT_H_
inline void __cufftSafeCall( cufftResult err, const char *file, const int line) {
	if( CUFFT_SUCCESS != err) {
		fprintf(stderr, "%s(%i) : cufftSafeCall() CUFFT error %d: ",
				file, line, (int)err);
		switch (err) {
			case CUFFT_INVALID_PLAN:   fprintf(stderr, "CUFFT_INVALID_PLAN"); break;
			case CUFFT_ALLOC_FAILED:   fprintf(stderr, "CUFFT_ALLOC_FAILED"); break;
			case CUFFT_INVALID_TYPE:   fprintf(stderr, "CUFFT_INVALID_TYPE"); break;
			case CUFFT_INVALID_VALUE:  fprintf(stderr, "CUFFT_INVALID_VALUE"); break;
			case CUFFT_INTERNAL_ERROR: fprintf(stderr, "CUFFT_INTERNAL_ERROR"); break;
			case CUFFT_EXEC_FAILED:    fprintf(stderr, "CUFFT_EXEC_FAILED"); break;
			case CUFFT_SETUP_FAILED:   fprintf(stderr, "CUFFT_SETUP_FAILED"); break;
			case CUFFT_INVALID_SIZE:   fprintf(stderr, "CUFFT_INVALID_SIZE"); break;
			case CUFFT_UNALIGNED_DATA: fprintf(stderr, "CUFFT_UNALIGNED_DATA"); break;
			default: fprintf(stderr, "CUFFT Unknown error code\n");
		}
		exit(-1);
	}
}
#endif

#endif /* _CUDA_SAFECALLS_H */
