#include "opt/optimize.h"

#define VERIFY_ARG(opt, arg)                                                                       \
	if(argi + 1 >= argc) {                                                                           \
		sup::print_err("error: missing argument '{}' for option '{}'\n", arg, opt);                    \
		return 1;                                                                                      \
	}

sup::i32 version() {
	sup::print("sup version 0 compiled on {}\n", __DATE__);
	return 0;
}

sup::i32 help() {
	sup::print("usage: sup [options] file\n");
	sup::print("options:\n");
	sup::print("  --version    display version infromation\n");
	sup::print("  --help       display this information\n");
	sup::print("  -e <list>    pass <list> of extensions to use\n");
	sup::print("  -p <num>     pass <num> specifying max program length\n");
	sup::print("  -l           list supported extensions\n");
	sup::print("\n");
	sup::print("for bug reports and issues, please visit:\n");
	sup::print("https://github.com/Goubermouche/sup\n");

	return 0;
}

sup::i32 list_e() {
	for(sup::u64 i = 0; i < sup::EXT_NAMES_SIZE; ++i) sup::print("{}\n", sup::EXT_NAMES[i]);
	return 0;
}

sup::i32 parse_e(sup::config& cfg, const char* p) {
	cfg.ext_mask = 0;
	while(*p) {
		while(*p == ' ' || *p == ',' || *p == '+') p++;
		if(!*p) break;

		const char* start = p;
		while(*p && *p != ' ' && *p != ',' && *p != '+') p++;

		bool found = false;
		for(sup::u32 i = 0; i < sup::EXT_NAMES_SIZE; ++i) {
			const char* ext = sup::EXT_NAMES[i];
			const char* s = start;

			while(s < p && *ext == *s) {
				ext++;
				s++;
			}

			if(s == p && *ext == '\0') {
				cfg.ext_mask |= (1u << i);
				found = true;
				break;
			}
		}

		if(!found) {
			char buf[32] = {0};
			sup::u64 len = (p - start < 31) ? (p - start) : 31;
			for(sup::u64 k = 0; k < len; ++k) buf[k] = start[k];
			sup::print_err("error: unknown extension '{}'\n", buf);
			return 1;
		}
	}

	return 0;
}

sup::i32 parse_u32(const char* src, sup::u32& out) {
	char* endptr;
	errno = 0;
	sup::u32 num = strtoul(src, &endptr, 10);

	if(errno == ERANGE) {
		sup::print_err("error: number is too large\n");
		return 1;
	}

	if(endptr == src) {
		sup::print_err("error: invalid number\n");
		return 1;
	}

	if(*endptr != '\0') {
		sup::print_err("error: invalid number\n");
		return 1;
	}

	out = num;
	return 0;
}

sup::i32 read_file(const char* filename, char** out) {
	FILE* file = fopen(filename, "rb");
	if(!file) {
		sup::print_err("error: cannot open file '{}'\n", filename);
		return 1;
	}

	fseek(file, 0, SEEK_END);
	sup::i32 length = ftell(file);
	fseek(file, 0, SEEK_SET);

	if(length < 0) {
		fclose(file);
		sup::print_err("error: cannot read file size\n");
		return 1;
	}

	char* buffer = (char*)malloc(length + 1);
	if(!buffer) {
		fclose(file);
		sup::print_err("error: cannot allocate file buffer\n");
		return 1;
	}

	sup::u64 read_bytes = fread(buffer, 1, length, file);
	buffer[read_bytes] = '\0';
	fclose(file);
	*out = buffer;

	return 0;
}

sup::i32 main(sup::i32 argc, char** argv) {
	sup::config cfg;
	sup::i32 argi = 1;
	char* source = 0;

	// parse arguments
	for(; argi < argc; ++argi) {
		if(argv[argi][0] != '-') {
			sup::i32 res = read_file(argv[argi], &source);
			if(res) { return res; }
		} else if(!std::strcmp(argv[argi], "--version")) {
			return version();
		} else if(!std::strcmp(argv[argi], "--help")) {
			return help();
		} else if(!std::strcmp(argv[argi], "-e")) {
			VERIFY_ARG("-e", "<list>");
			sup::i32 res = parse_e(cfg, argv[++argi]);
			if(res) { return res; }
		} else if(!std::strcmp(argv[argi], "-p")) {
			VERIFY_ARG("-p", "<num>");
			sup::i32 res = parse_u32(argv[++argi], cfg.max_prog_len);
			if(res) { return res; }
		} else if(!std::strcmp(argv[argi], "-l")) {
			return list_e();
		} else {
			sup::print_err("error: unknown command line option '{}'\n", argv[argi]);
			return 1;
		}
	}

	if(source == 0) {
		sup::print_err("error: missing source file\n");
		return 1;
	}

	// run
	if(sup::device_init()) { return 1; }

	sup::optimize(source, cfg);
	return 0;
}
