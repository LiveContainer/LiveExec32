const char *TARGET_ARMV7 = "\
<?xml version=\"1.0\"?> \
<target version=\"1.0\"> \
<architecture>arm</architecture> \
<feature name=\"com.apple.debugserver.arm\"> \
  <reg name=\"r0\" regnum=\"0\" offset=\"0\" bitsize=\"32\" group=\"general\" generic=\"arg1\"/> \
  <reg name=\"r1\" regnum=\"1\" offset=\"4\" bitsize=\"32\" group=\"general\" generic=\"arg2\"/> \
  <reg name=\"r2\" regnum=\"2\" offset=\"8\" bitsize=\"32\" group=\"general\" generic=\"arg3\"/> \
  <reg name=\"r3\" regnum=\"3\" offset=\"12\" bitsize=\"32\" group=\"general\" generic=\"arg4\"/> \
  <reg name=\"r4\" regnum=\"4\" offset=\"16\" bitsize=\"32\" group=\"general\"/> \
  <reg name=\"r5\" regnum=\"5\" offset=\"20\" bitsize=\"32\" group=\"general\"/> \
  <reg name=\"r6\" regnum=\"6\" offset=\"24\" bitsize=\"32\" group=\"general\"/> \
  <reg name=\"r7\" regnum=\"7\" offset=\"28\" bitsize=\"32\" group=\"general\" generic=\"fp\"/> \
  <reg name=\"r8\" regnum=\"8\" offset=\"32\" bitsize=\"32\" group=\"general\"/> \
  <reg name=\"r9\" regnum=\"9\" offset=\"36\" bitsize=\"32\" group=\"general\"/> \
  <reg name=\"r10\" regnum=\"10\" offset=\"40\" bitsize=\"32\" group=\"general\"/> \
  <reg name=\"r11\" regnum=\"11\" offset=\"44\" bitsize=\"32\" group=\"general\"/> \
  <reg name=\"r12\" regnum=\"12\" offset=\"48\" bitsize=\"32\" group=\"general\"/> \
  <reg name=\"sp\" regnum=\"13\" offset=\"52\" bitsize=\"32\" group=\"general\" generic=\"sp\"/> \
  <reg name=\"lr\" regnum=\"14\" offset=\"56\" bitsize=\"32\" group=\"general\" generic=\"ra\"/> \
  <reg name=\"pc\" regnum=\"15\" offset=\"60\" bitsize=\"32\" group=\"general\" generic=\"pc\"/> \
  <reg name=\"cpsr\" regnum=\"16\" offset=\"64\" bitsize=\"32\" group=\"general\" generic=\"flags\"/> \
</feature> \
</target> \
";
