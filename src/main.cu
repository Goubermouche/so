#include "opt/optimize.h"

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
	fprintf(stderr, "  -p <num>     pass <num> specifying max program length\n");
	fprintf(stderr, "  -l           list supported extensions\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "for bug reports and issues, please visit:\n");
	fprintf(stderr, "https://github.com/Goubermouche/sup\n");

	return 0;
}

i32 list_e() {
	for(u64 i = 0; i < EXT_COUNT; ++i) printf("%s\n", EXT_NAMES[i]);
	return 0;
}

i32 parse_e(opt_config* cfg, const char* p) {
	cfg->ext_mask = 0;
	while(*p) {
		while(*p == ' ' || *p == ',' || *p == '+') p++;
		if(!*p) break;

		const char* start = p;
		while(*p && *p != ' ' && *p != ',' && *p != '+') p++;

		bool found = false;
		for(u32 i = 0; i < EXT_COUNT; ++i) {
			const char* ext = EXT_NAMES[i];
			const char* s = start;

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
			char buf[32] = {0};
			u64 len = (p - start < 31) ? (p - start) : 31;
			for(u64 k = 0; k < len; ++k) buf[k] = start[k];
			fprintf(stderr, "error: unknown extension '%s'\n", buf);
			return 1;
		}
	}

	return 0;
}

i32 parse_u32(const char* src, u32& out) {
	char* endptr;
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

i32 read_file(const char* filename, char** out) {
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

	char* buffer = (char*)malloc(length + 1);
	if(!buffer) {
		fclose(file);
		fprintf(stderr, "error: cannot allocate file buffer\n");
		return 1;
	}

	u64 read_bytes = fread(buffer, 1, length, file);
	buffer[read_bytes] = '\0';
	fclose(file);
	*out = buffer;

	return 0;
}

i32 main(i32 argc, char** argv) {
	opt_config cfg = opt_make_default_config();
	i32 argi = 1;
	char* source = 0;

	// parse arguments
	for(; argi < argc; ++argi) {
		if(argv[argi][0] != '-') {
			i32 res = read_file(argv[argi], &source);
			if(res) { return res; }
		} else if(!strcmp(argv[argi], "--version")) {
			return version();
		} else if(!strcmp(argv[argi], "--help")) {
			return help();
		} else if(!strcmp(argv[argi], "-e")) {
			VERIFY_ARG("-e", "<list>");
			i32 res = parse_e(&cfg, argv[++argi]);
			if(res) { return res; }
		} else if(!strcmp(argv[argi], "-p")) {
			VERIFY_ARG("-p", "<num>");
			i32 res = parse_u32(argv[++argi], cfg.max_prog_len);
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

	program parsed = program::parse(source);
	opt_run(&parsed, &cfg);
	return 0;
}
