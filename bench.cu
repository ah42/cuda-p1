#include "bench.h"

int isReasonable(int fft) {  //From an idea of AXN's mentioned on the forums
	int i;
	int b[4] = { 2, 3, 5, 7 };
	double logb;
	int maxv;
	int out[4] = { 0, 0, 0, 0 };

	for (i = 0; i < 4; i++) {
		logb = log(b[i]);
		/* determine max value of x^y to cover input fft*/
		maxv = (int)ceil(log(fft) / logb);
		while (maxv > 0) {
			if (ceil((float)fft / powf(b[i], maxv)) == floor((float)fft / powf(b[i], maxv))) {
				out[i] = maxv;
				maxv = 0;
			} else {
				maxv--;
			}
		}
	}

	if (
		(out[0] > 0 && out[1] > 0 && out[2] > 0 && out[3] > 0) /* best fftlen only have max 3 bases. if we need more, it's not automatically good */
		|| powf(b[0], out[0]) *powf(b[1], out[1]) * powf(b[2],out[2]) *powf(b[3],out[3]) != fft /* if fft has a divisor outside of 2, 3, 5, or 7, this check will fail */
		|| out[0]+out[1]+out[2]+out[3] == 0 /* none of these? must be invalid */
		|| out[0] == 0 /* must have a base of 2 */
		) {
		return (0);
	} else {
		return (1);
	}
}

void threadbench(int n, int passes, int device_number) {
	float outerTime, maxerr = 0.5f;
	int threads[6] = {32, 64, 128, 256, 512, 1024};

	/* I could just hard-code this value, but it's better to be safe */
	const int sizeofThreads = sizeof(threads)/sizeof(threads[0]);

	float total[sizeofThreads * sizeofThreads * sizeofThreads] = {0.0f};
	float squareTime[sizeofThreads];
	int t1, t2, t3, i, j;
	float best_time = 10000.0f;
	int best_t1 = 0, best_t2 = 0, best_t3 = 0;
	int pass;
	cudaEvent_t start, stop;

	printf("CUDA bench, testing various thread sizes for fft %dK, doing %d passes.\n", n, passes);
	fflush (NULL);
	n *= 1024;

	cutilSafeCall(cudaMalloc((void **) &g_x, sizeof(double) * n));
	cutilSafeCall(cudaMemset(g_x, 0, sizeof(double) * n));
	cutilSafeCall(cudaMalloc((void **) &g_ttmp, sizeof(double) * n));
	cutilSafeCall(cudaMemset(g_ttmp, 0, sizeof(double) * n));
	cutilSafeCall(cudaMalloc((void **) &g_ct, sizeof(double) * n / 4));
	cutilSafeCall(cudaMemset(g_ct, 0, sizeof(double) * n / 4));
	cutilSafeCall(cudaMalloc((void **) &g_ttp1, sizeof(double) * n / 32));
	cutilSafeCall(cudaMalloc((void **) &g_datai, sizeof(int) * n / 32));
	cutilSafeCall(cudaMalloc((void **) &g_carryi, sizeof(int) * n / 64));
	cutilSafeCall(cudaMalloc((void **) &g_err, sizeof(float)));
	cutilSafeCall(cudaMemset(g_err, 0, sizeof(float)));

	cutilSafeCall(cudaEventCreate(&start));
	cutilSafeCall(cudaEventCreateWithFlags(&stop, cudaEventBlockingSync));
	cufftSafeCall(cufftPlan1d(&plan, n / 2, CUFFT_Z2Z, 1));

	for (t2 = 0; t2 < sizeofThreads && !quitting; t2++) {
		/* bench cudaAcc_square threads */
		squareTime[t2] = 0.0f;

		for (pass = 1; pass <= passes+3 && !quitting; pass++) {
			cutilSafeCall(cudaEventRecord(start, 0));
			for (i = 0; i < 100; i++) { /* 250 loops */
				cudaAcc_square(threads[t2], n, g_x, g_ct);
			}
			cutilSafeCall(cudaEventRecord(stop, 0));
			cutilSafeCall(cudaEventSynchronize(stop));
			cutilSafeCall(cudaEventElapsedTime(&outerTime, start, stop));
			outerTime /= 100.0f;

			if (pass >=3) /* ignore the first 3: they have an unstable time, afterwards the time settles down */
				squareTime[t2] += outerTime;
		}
		printf("fft size = %dK, square time = %2.4f msec, threads %d\n", n/1024, squareTime[t2]/passes, threads[t2]);
	}

	best_time = FLT_MAX;
	for (t2 = 0; t2 < sizeofThreads && !quitting; t2++) {
		if (squareTime[t2] < best_time && squareTime[t2] > 0.0f) {
			best_time = squareTime[t2];
			best_t2 = t2;
		}
	}

	printf("\nBest square time for fft = %dK, time: %2.4f, t = %d\n\n", n / 1024, best_time / passes, threads[best_t2]);

	for (t1 = 0; t1 < sizeofThreads - 1 && !quitting; t1++) {
		/* bench norm1a/2a threads */
		if (n / (2 * threads[t1]) <= dev.maxGridSize[0] && n % (2 * threads[t1]) == 0) {
			for (t3 = 0; t3 < sizeofThreads && !quitting; t3++) {
				for (pass = 1; pass <= passes + 3 && !quitting; pass++) {
					cutilSafeCall(cudaEventRecord(start, 0));
					for (i = 0; i < 100 && !quitting; i++) {
						//cufftSafeCall(cufftExecZ2Z(plan, (cufftDoubleComplex *) g_x, (cufftDoubleComplex *) g_x, CUFFT_INVERSE));
						//cudaAcc_square(threads[best_t2], n, g_x, g_ct);
						//cufftSafeCall(cufftExecZ2Z(plan, (cufftDoubleComplex *) g_x, (cufftDoubleComplex *) g_x, CUFFT_INVERSE));
						cudaAcc_norm1a(0, 1, threads[t1], n, g_x, g_datai, g_xint, g_ttmp, g_carryi, g_err, maxerr);
						cudaAcc_norm2a(0, threads[t1], threads[t3], g_x, g_xint, n, g_datai, g_carryi, g_ttp1);
					}
					cutilSafeCall(cudaEventRecord(stop, 0));
					cutilSafeCall(cudaEventSynchronize(stop));
					cutilSafeCall(cudaEventElapsedTime(&outerTime, start, stop));
					outerTime /= 100.0f;

					if (pass >= 3) /* ignore the first 3: they have an unstable time, afterwards the time settles down */
						total[36 * t1 + 6 * best_t2 + t3] += outerTime;
				}

				printf("fft size = %dK, ave time = %2.4f msec, Norm1 threads %d, Norm2 threads %d\n", n / 1024,
						total[36 * t1 + 6 * best_t2 + t3] / passes, threads[t1], threads[t3]);
				fflush(NULL);

			}
		}
	}

	/* @@ above inner loop is a good place for cuda call error return checking to be added to perhaps detect failed calls
	or the 1024-threads error on certain cards; it may impact benchmark performance but not actual usage performance. */

	/* Detect abnormally low iteration times */

	float averagetime=0.0f;
	int thresholdwarncount=0;
	float thresholdratio=0.75f;
	if ( n / 1024 < 100 )
		thresholdratio= 0.1f + 0.65f * n / 102400.0f; /* tapers from 0.1 to 0.8 linearly with n up to 100k, then flat at 0.75 */

	j = 0;
	for (i=0; i < 216; i++) {
		if (total[i] > 0) {
			averagetime += total[i];
			j++;
		}
	}

	averagetime=averagetime/float(j);
	float thresholdtime=averagetime*thresholdratio;
	printf("\nAverage time for fft= %dK, all threads variations %3.4f msec, threshold value for valid timings set to %1.4f of this, %3.4f msec\n",
		n/1024, averagetime / passes, thresholdratio, thresholdtime / passes);

	best_time = FLT_MAX;

	for (i = 0; i < 216 && !quitting; i++) {
		if (total[i] < best_time && total[i] > 0.0f) {
			if (total[i] > thresholdtime) {
				int j = i;
				best_time = total[i];
				best_t3 = j % 6;
				j /= 6;
				best_t1 = j / 6;
			} else {
				printf("Warning, time for fft = %dK, time: %3.4f msec, t1 = %d, t2 = %d, t3 = %d is below threshold %3.4f msec (%1.4f of average %3.4f)\n",
					n / 1024, total[i] / passes, threads[i / 36], threads[best_t2], threads[i%6], thresholdtime / passes, thresholdratio, averagetime / passes);
				thresholdwarncount++;
			}
		}
	}

	if (thresholdwarncount > 0) {
		printf("Timings below threshold were detected for %d norm1 / mult / norm2 combinations for fft length %dK and omitted from consideration for best.\n",
			thresholdwarncount, n / 1024);
	}

	printf("\nBest time for fft = %dK, time: %2.4f, t1 = %d, t2 = %d, t3 = %d\n", n / 1024, best_time / passes, threads[best_t1],
			threads[best_t2], threads[best_t3]);

	cufftSafeCall(cufftDestroy(plan));
	cutilSafeCall(cudaFree((char *) g_x));
	cutilSafeCall(cudaFree((char *) g_ttmp));
	cutilSafeCall(cudaFree((char *) g_ttp1));
	cutilSafeCall(cudaFree((char *) g_ct));
	cutilSafeCall(cudaFree((char *) g_datai));
	cutilSafeCall(cudaFree((char *) g_carryi));
	cutilSafeCall(cudaFree((char *) g_err));
	cutilSafeCall(cudaEventDestroy(start));
	cutilSafeCall(cudaEventDestroy(stop));

	char threadfile[256];
	char devname[256];
	remove_spaces(devname, dev.name);

	if (!quitting) {
		sprintf(threadfile, "%s_threads.txt", devname);
		FILE *fptr;
		fptr = fopen(threadfile, "a+");
		if (!fptr)
			printf("Can't open %s_threads.txt\n", devname);
		else
			fprintf(fptr, "%5d %4d %4d %4d %8.4f\n", n / 1024, threads[best_t1], threads[best_t2], threads[best_t3], best_time / passes);
	}
}

void cufftbench(int cufftbench_s, int cufftbench_e, int passes, int device_number) {
//if(cufftbench_s % 2) cufftbench_s++;

	cudaEvent_t start, stop;
	float outerTime;
	int i, j, k;
	int end = cufftbench_e - cufftbench_s + 1;
	float best_time;
	float *total, *max_diff, maxerr = 0.5f;
	int threads[] = {32, 64, 128, 256, 512, 1024};
	int t1 = 3, t2 = 2, t3 = 2;

	if (end == 1) {
		threadbench(cufftbench_e, passes, device_number);
		return;
	}

	printf("CUDA bench, testing reasonable fft sizes %dK to %dK, doing %d passes.\n", cufftbench_s, cufftbench_e, passes);

	total = (float *) malloc(sizeof(float) * end);
	max_diff = (float *) malloc(sizeof(float) * end);
	for (i = 0; i < end; i++) {
		total[i] = max_diff[i] = 0.0f;
	}

	cutilSafeCall(cudaMalloc((void **) &g_x, sizeof(double) * 1024 * cufftbench_e));
	cutilSafeCall(cudaMemset(g_x, 0, sizeof(double) * 1024 * cufftbench_e));
	cutilSafeCall(cudaMalloc((void **) &g_ttmp, sizeof(double) * 1024 * cufftbench_e));
	cutilSafeCall(cudaMemset(g_ttmp, 0, sizeof(double) * 1024 * cufftbench_e));
	cutilSafeCall(cudaMalloc((void **) &g_ct, sizeof(double) * 256 * cufftbench_e));
	cutilSafeCall(cudaMemset(g_ct, 0, sizeof(double) * 256 * cufftbench_e));
	cutilSafeCall(cudaMalloc((void **) &g_ttp1, sizeof(double) * 1024 / 32 * cufftbench_e));
	cutilSafeCall(cudaMalloc((void **) &g_datai, sizeof(int) * 1024 / 32 * cufftbench_e));
	cutilSafeCall(cudaMalloc((void **) &g_carryi, sizeof(int) * 512 / 32 * cufftbench_e));
	cutilSafeCall(cudaMalloc((void **) &g_err, sizeof(float)));
	cutilSafeCall(cudaMemset(g_err, 0, sizeof(float)));

	cutilSafeCall(cudaEventCreate(&start));
	cutilSafeCall(cudaEventCreateWithFlags(&stop, cudaEventBlockingSync));

	for (j = cufftbench_s; j <= cufftbench_e && !quitting; j++) {
		if (isReasonable(j) == 1) {
			int n = j * 1024;
			cufftSafeCall(cufftPlan1d(&plan, n / 2, CUFFT_Z2Z, 1));
			for (k = 0; k < passes && !quitting; k++) {
				cutilSafeCall(cudaEventRecord(start, 0));
				for (i = 0; i < 50 && !quitting; i++) {
					cufftSafeCall(cufftExecZ2Z(plan, (cufftDoubleComplex *) g_x, (cufftDoubleComplex *) g_x, CUFFT_INVERSE));
					cudaAcc_square(threads[t2], n, g_x, g_ct);
					cufftSafeCall(cufftExecZ2Z(plan, (cufftDoubleComplex *) g_x, (cufftDoubleComplex *) g_x, CUFFT_INVERSE));
					cudaAcc_norm1a(0, 0, threads[t1], n, g_x, g_datai, g_xint, g_ttmp, g_carryi, g_err, maxerr);
					cudaAcc_norm2a(0, threads[t1], threads[t3], g_x, g_xint, n, g_datai, g_carryi, g_ttp1);
				}
				cutilSafeCall(cudaEventRecord(stop, 0));
				cutilSafeCall(cudaEventSynchronize(stop));
				cutilSafeCall(cudaEventElapsedTime(&outerTime, start, stop));
				i = j - cufftbench_s;
				outerTime /= 50.0f;
				total[i] += outerTime;
				if (outerTime > max_diff[i])
					max_diff[i] = outerTime;
			}
			cufftSafeCall(cufftDestroy(plan));
			printf("fft size = %dK, ave time = %2.4f msec, max-ave = %0.5f\n", j, total[i] / passes, max_diff[i] - total[i] / passes);
			fflush (NULL);
		}
	}
	cutilSafeCall(cudaFree((char *) g_x));
	cutilSafeCall(cudaFree((char *) g_ttmp));
	cutilSafeCall(cudaFree((char *) g_ttp1));
	cutilSafeCall(cudaFree((char *) g_ct));
	cutilSafeCall(cudaFree((char *) g_datai));
	cutilSafeCall(cudaFree((char *) g_carryi));
	cutilSafeCall(cudaFree((char *) g_err));
	cutilSafeCall(cudaEventDestroy(start));
	cutilSafeCall(cudaEventDestroy(stop));

	float totaltime = 0.0f;
	unsigned int totallen = 0;

	for (i = end - 1; i >0; i--) {
		if (total[i] > 0.0f) {
			totaltime += total[i] / float(passes);
			totallen += cufftbench_s + i;
		}
	}

	/* Average time/fftlength
	Use the inverse for higher reliability from lower run-times.
	*/
	float totalavg = float(totallen) / totaltime;

	printf("totalavg: %4.4f\ttotallen: %d\ttotaltime: %5.4f\n\n", totalavg, totallen, totaltime);

	i = end - 1;
	best_time = FLT_MAX;
	while (i >= 0 && !quitting) {
		if (total[i] > 0.0f && fabsf(((cufftbench_s + i) / total[i]) / totalavg) >= 5.0f) {
			printf("Invalid timings for fft length %dK, removing from results\n", cufftbench_s + i);
			total[i] = 0.0f;
		}

		if (total[i] > 0.0f && total[i] < best_time) {
			best_time = total[i];
		} else {
			total[i] = 0.0f;
		}
		i--;
	}

	if (!quitting) {
		char fftfile[256];
		char devname[256];
		remove_spaces(devname, dev.name);

		FILE *fptr;

		sprintf(fftfile, "%s_fft.txt", devname);
		fptr = fopen(fftfile, "w");
		if (!fptr) {
			printf("Cannot open %s.\n", fftfile);
			printf("Device              %s\n", dev.name);
			printf("Compatibility       %d.%d\n", dev.major, dev.minor);
			printf("clockRate (MHz)     %d\n", dev.clockRate / 1000);
			printf("memClockRate (MHz)  %d\n", dev.memoryClockRate / 1000);
			printf("\n  fft    max exp  ms/iter\n");
			for (i = 0; i < end; i++) {
				if (total[i] > 0.0f) {
					int tl = (int)(exp(0.9784876919 * log((double)cufftbench_s + i)) * 22366.92473079 / 1.01);
					if (tl % 2 == 0)
						tl -= 1;
					while (!isprime(tl))
						tl -= 2;
					printf("%5d %10d %8.4f\n", cufftbench_s + i, tl, total[i] / passes);
				}
			}
			fflush(NULL);
		}
		else {
			fprintf(fptr, "Device              %s\n", dev.name);
			fprintf(fptr, "Compatibility       %d.%d\n", dev.major, dev.minor);
			fprintf(fptr, "clockRate (MHz)     %d\n", dev.clockRate / 1000);
			fprintf(fptr, "memClockRate (MHz)  %d\n", dev.memoryClockRate / 1000);
			fprintf(fptr, "\n  fft    max exp  ms/iter\n");
			for (i = 0; i < end; i++) {
				if (total[i] > 0.0f) {
					int tl = (int)(exp(0.9784876919 * log((double)cufftbench_s + i)) * 22366.92473079 / 1.01);
					if (tl % 2 == 0)
						tl -= 1;
					while (!isprime(tl))
						tl -= 2;
					fprintf(fptr, "%5d %10d %8.4f\n", cufftbench_s + i, tl, total[i] / passes);
				}
			}
			fclose(fptr);
			printf("Optimal fft lengths saved in %s.\nPlease email a copy to james@mersenne.ca.\n", fftfile);
			fflush(NULL);
		}
	}

	free((char *) total);
	free((char *) max_diff);
}
