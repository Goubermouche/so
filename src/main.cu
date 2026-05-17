#include "optimize/optimize.h"

#define VERIFY_ARG(opt, arg)                                                                       \
	if(argi + 1 >= argc) {                                                                           \
		fprintf(stderr, "error: missing argument '%s' for option '%s'\n", arg, opt);                   \
		return 1;                                                                                      \
	}

i32 version() {
	printf("sup version 0 compiled on %s\n", __DATE__);
	return 0;
}

i32 help() {
	fprintf(stderr, "usage: sup [options] file\n");
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

i32 list_e() {
	for(u64 i = 0; i < CPU_EXT_COUNT; ++i) printf("%s\n", CPU_EXT_NAMES[i]);
	return 0;
}

i32 parse_e(opt_cfg* cfg, const c8* p) {
	cfg->ext_mask = 0;
	while(*p) {
		while(*p == ' ' || *p == ',' || *p == '+') p++;
		if(!*p) break;

		const c8* start = p;
		while(*p && *p != ' ' && *p != ',' && *p != '+') p++;

		bool found = false;
		for(u32 i = 0; i < CPU_EXT_COUNT; ++i) {
			const c8* ext = CPU_EXT_NAMES[i];
			const c8* s = start;

			while(s < p && *ext == *s) {
				ext++;
				s++;
			}

			if(s == p && *ext == '\0') {
				cfg->ext_mask |= (1u << i);
				found = true;
				break;
			}
		}

		if(!found) {
			c8 buf[32] = {0};
			u64 len = (p - start < 31) ? (p - start) : 31;
			for(u64 k = 0; k < len; ++k) buf[k] = start[k];
			fprintf(stderr, "error: unknown extension '%s'\n", buf);
			return 1;
		}
	}

	return 0;
}

i32 parse_u32(const c8* src, u32& out) {
	c8* endptr;
	errno = 0;
	u32 num = strtoul(src, &endptr, 10);

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

i32 read_file(const c8* filename, c8** out, u64* out_len) {
	FILE* file = fopen(filename, "rb");
	if(!file) {
		fprintf(stderr, "error: cannot open file '%s'\n", filename);
		return 1;
	}

	fseek(file, 0, SEEK_END);
	i32 length = ftell(file);
	fseek(file, 0, SEEK_SET);

	if(length < 0) {
		fclose(file);
		fprintf(stderr, "error: cannot read file size\n");
		return 1;
	}

	c8* buffer = (c8*)malloc(length + 1);
	if(!buffer) {
		fclose(file);
		fprintf(stderr, "error: cannot allocate file buffer\n");
		return 1;
	}

	u64 read_bytes = fread(buffer, 1, length, file);
	buffer[read_bytes] = '\0';
	fclose(file);
	*out = buffer;
	*out_len = read_bytes;

	return 0;
}

i32 main(i32 argc, c8** argv) {
	opt_cfg cfg = opt_cfg_make_default();
	i32 argi = 1;
	c8* source = 0;
	u64 source_len = 0;
	u32 run_count = 1;

	// parse arguments
	for(; argi < argc; ++argi) {
		if(argv[argi][0] != '-') {
			i32 res = read_file(argv[argi], &source, &source_len);
			if(res) { return res; }
		} else if(!strcmp(argv[argi], "--version")) {
			return version();
		} else if(!strcmp(argv[argi], "--help")) {
			return help();
		} else if(!strcmp(argv[argi], "-e")) {
			VERIFY_ARG("-e", "<list>");
			i32 res = parse_e(&cfg, argv[++argi]);
			if(res) { return res; }
		} else if(!strcmp(argv[argi], "-r")) {
			VERIFY_ARG("-r", "<num>");
			i32 res = parse_u32(argv[++argi], run_count);
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
	cpu_inst_db_load();

	for(u32 run = 0; run < run_count; ++run) {
		cpu_program parsed = cpu_program_parse(str(source, source_len));
		opt_run(&parsed, &cfg);
		cpu_program_free(&parsed);
	}

	return 0;
}
