/*
 * Apple libiconv compatibility surface for the bundled conversion core
 * (see iconv.c). Covers the GNU libiconv 1.11 API that Apple's
 * /usr/lib/libiconv.2.dylib exports, plus the legacy __iconv aliases.
 */
#include <iconv.h>
#include <errno.h>
#include <stddef.h>

int _libiconv_version = _LIBICONV_VERSION;

const char *iconv_canonicalize(const char *name)
{
	/* The bundled core folds case, punctuation and aliases when it resolves
	 * encoding names, so the input name is already usable as-is. */
	return name;
}

void iconvlist(int (*do_one)(unsigned int namescount,
	const char * const * names, void *data), void *data)
{
	static const char *const charsets[] = {
		"UTF-8", "UTF-16BE", "UTF-16LE", "UTF-16",
		"UTF-32BE", "UTF-32LE", "UTF-32",
		"UCS-2BE", "UCS-2LE", "UCS-2",
		"UCS-4BE", "UCS-4LE", "UCS-4",
		"US-ASCII",
		"ISO-8859-1",
		"EUC-JP", "SHIFT_JIS", "CP932", "ISO-2022-JP",
		"GB18030", "GBK", "GB2312",
		"BIG5", "CP950", "BIG5-HKSCS",
		"EUC-KR", "CP949", "KSC5601", "KSX1001",
	};

	if (!do_one) return;
	for (size_t i = 0;
			i < sizeof(charsets) / sizeof(charsets[0]);
			i++) {
		const char *names[1] = { charsets[i] };
		do_one(1, names, data);
	}
}

void libiconv_set_relocation_prefix(const char *orig_prefix,
	const char *curr_prefix)
{
	(void)orig_prefix;
	(void)curr_prefix;
}

/* Legacy private aliases that Apple's libiconv exports. */
iconv_t __iconv_open(const char *tocode, const char *fromcode)
{
	return iconv_open(tocode, fromcode);
}

size_t __iconv(iconv_t cd, char **inbuf, size_t *inbytesleft,
	char **outbuf, size_t *outbytesleft)
{
	return iconv(cd, inbuf, inbytesleft, outbuf, outbytesleft);
}

int __iconv_close(iconv_t cd)
{
	return iconv_close(cd);
}
