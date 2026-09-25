#include <pappl-retrofit/pappl-retrofit-private.h>
#include <stdio.h>

extern const char *ps_autoadd(const char *device_info, const char *device_uri,
                              const char *device_id, void *data);

int main(void)
{
  pr_printer_app_global_data_t empty_drivers = {0};
  const char *unknown_ps = "MFG:Unknown;MDL:Unsupported Printer;CMD:POSTSCRIPT;";

  /* Exercise the real retrofit matcher before calling the production callback. */
  if (prBestMatchingPPD(unknown_ps, &empty_drivers) != NULL)
    return 2;

  if (ps_autoadd("Unsupported Printer", "cups:socket://127.0.0.1:19999",
                 unknown_ps, &empty_drivers) != NULL)
  {
    fputs("Unknown PostScript printer must not be auto-added\n", stderr);
    return 1;
  }

  return 0;
}
