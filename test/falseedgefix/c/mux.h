#ifndef MUX_H
#define MUX_H

/* A struct and an enum spelled like functions the program calls. */
struct opts_parse {
	const char *template;
	int lower;
	int upper;
};

enum find_type {
	FIND_PANE,
	FIND_WINDOW,
	FIND_SESSION
};

struct args *opts_parse(const struct opts_parse *, const char **, int);
int window_count(void);

#endif
