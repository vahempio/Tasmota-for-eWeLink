#include "be_constobj.h"

static be_define_const_map_slots(be_class_AudioFileSource_map) {
    { be_const_key_weak(_X2Ep, -1), be_const_var(0) },
};

static be_define_const_map(
    be_class_AudioFileSource_map,
    1
);

BE_EXPORT_VARIABLE be_define_const_class(
    be_class_AudioFileSource,
    1,
    NULL,
    AudioFileSource
);
