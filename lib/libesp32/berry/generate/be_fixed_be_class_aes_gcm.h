#include "be_constobj.h"

static be_define_const_map_slots(be_class_aes_gcm_map) {
    { be_const_key_weak(encrypt, 4), be_const_func(m_aes_gcm_encryt) },
    { be_const_key_weak(_X2Ep2, -1), be_const_var(0) },
    { be_const_key_weak(decrypt, -1), be_const_func(m_aes_gcm_decryt) },
    { be_const_key_weak(init, -1), be_const_func(m_aes_gcm_init) },
    { be_const_key_weak(_X2Ep1, -1), be_const_var(1) },
    { be_const_key_weak(tag, -1), be_const_func(m_aes_gcm_tag) },
};

static be_define_const_map(
    be_class_aes_gcm_map,
    6
);

BE_EXPORT_VARIABLE be_define_const_class(
    be_class_aes_gcm,
    2,
    NULL,
    AES_GCM
);
