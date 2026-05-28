#include "optimize/optimize.h"

#define VerifyArg(opt, arg)                                                                        \
	if(argi + 1 >= argc) {                                                                           \
		fprintf(stderr, "error: missing argument '%s' for option '%s'\n", arg, opt);                   \
		return 1;                                                                                      \
	}

I32 version() {
	printf("sup version 0 compiled on %s\n", __DATE__);
	return 0;
}

I32 help() {
	fprintf(stderr, "usage: sup [options] <file>\n");
	fprintf(stderr, "options:\n");
	fprintf(stderr, "  --version    display version infromation\n");
	fprintf(stderr, "  --help       display this information\n");
	fprintf(stderr, "  -e <list>    pass <list> of extensions to use\n");
	fprintf(stderr, "  -r <num>     pass <num> specifying number of runs to execute\n");
	fprintf(stderr, "  -l           list supported extensions\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "for bug reports and issues, please visit:\n");
	fprintf(stderr, "https://github.com/Goubermouche/sup\n");

	return 0;
}

I32 list_e() {
	for(U64 i = 0; i < DatabaseExtensionCount; ++i) printf("%s\n", DatabaseExtensionNames[i].ptr);
	return 0;
}

I32 parse_e(OptimizerOptions& opt, C8* p) {
	opt.ext_mask = 0;
	while(*p) {
		while(*p == ' ' || *p == ',' || *p == '+') p++;
		if(!*p) break;

		C8* start = p;
		while(*p && *p != ' ' && *p != ',' && *p != '+') p++;

		B32 found = false;
		for(U32 i = 0; i < DatabaseExtensionCount; ++i) {
			C8* ext = DatabaseExtensionNames[i].ptr;
			C8* s = start;

			while(s < p && *ext == *s) {
				ext++;
				s++;
			}

			if(s == p && *ext == '\0') {
				opt.ext_mask |= (1u << i);
				found = true;
				break;
			}
		}

		if(!found) {
			C8 buf[32] = {0};
			U64 len = (p - start < 31) ? (p - start) : 31;
			for(U64 k = 0; k < len; ++k) buf[k] = start[k];
			fprintf(stderr, "error: unknown extension '%s'\n", buf);
			return 1;
		}
	}

	return 0;
}

I32 parse_u32(C8* src, U32& out) {
	C8* endptr;
	errno = 0;
	U32 num = strtoul(src, &endptr, 10);

	if(errno == ERANGE) {
		fprintf(stderr, "error: number is too large\n");
		return 1;
	}

	if(endptr == src) {
		fprintf(stderr, "error: invalid number\n");
		return 1;
	}

	if(*endptr != '\0') {
		fprintf(stderr, "error: invalid number\n");
		return 1;
	}

	out = num;
	return 0;
}

I32 read_file(C8* filename, C8** out, U64* out_len) {
	FILE* file = fopen(filename, "rb");
	if(!file) {
		fprintf(stderr, "error: cannot open file '%s'\n", filename);
		return 1;
	}

	fseek(file, 0, SEEK_END);
	I32 length = ftell(file);
	fseek(file, 0, SEEK_SET);

	if(length < 0) {
		fclose(file);
		fprintf(stderr, "error: cannot read file size\n");
		return 1;
	}

	C8* buffer = (C8*)malloc(length + 1);
	if(!buffer) {
		fclose(file);
		fprintf(stderr, "error: cannot allocate file buffer\n");
		return 1;
	}

	U64 read_bytes = fread(buffer, 1, length, file);
	buffer[read_bytes] = '\0';
	fclose(file);
	*out = buffer;
	*out_len = read_bytes;

	return 0;
}

I32 main(I32 argc, C8** argv) {
	OptimizerOptions opt;
	optimizer_make_default_options(&opt);
	I32 argi = 1;
	C8* source = 0;
	U64 source_len = 0;
	U32 run_count = 1;

	// parse arguments
	for(; argi < argc; ++argi) {
		if(argv[argi][0] != '-') {
			I32 res = read_file(argv[argi], &source, &source_len);
			if(res) { return res; }
		} else if(!strcmp(argv[argi], "--version")) {
			return version();
		} else if(!strcmp(argv[argi], "--help")) {
			return help();
		} else if(!strcmp(argv[argi], "-e")) {
			VerifyArg("-e", "<list>");
			I32 res = parse_e(opt, argv[++argi]);
			if(res) { return res; }
		} else if(!strcmp(argv[argi], "-r")) {
			VerifyArg("-r", "<num>");
			I32 res = parse_u32(argv[++argi], run_count);
			if(res) { return res; }
		} else if(!strcmp(argv[argi], "-l")) {
			return list_e();
		} else {
			fprintf(stderr, "error: unknown command line option '%s'\n", argv[argi]);
			return 1;
		}
	}

	if(source == 0) {
		fprintf(stderr, "error: missing source file\n");
		return 1;
	}

	// run
	if(device_init()) { return 1; }
	instruction_db_load();

	for(U32 run = 0; run < run_count; ++run) {
		Arena* scratch = arena_make(0);
		Optimizer optimizer;
		optimizer_make(&optimizer, &opt);
		Program program;
		if(program_parse(&program, scratch, str_make(source, source_len))) {
			optimizer_free(&optimizer);
			arena_free(scratch);
			return 1;
		}
		if(optimizer_run(&optimizer, &program)) {
			optimizer_free(&optimizer);
			arena_free(scratch);
			return 1;
		}
		optimizer_free(&optimizer);
		arena_free(scratch);
	}

	return 0;
}
