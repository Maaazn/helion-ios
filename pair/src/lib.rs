//! Pairable-host FFI. mDNS is published by UIKit/NSNetService so the app
//! does not need the multicast entitlement. Handshake is idevice RPPairing (MIT).

use std::ffi::{CStr, CString, c_char, c_void};
use std::net::Ipv4Addr;
use std::ptr;

use idevice::remote_pairing::{PairableHost, PairableHostInfo, RpPairingFile, RpPairingSocket};

struct Ctx(*mut c_void);
unsafe impl Send for Ctx {}
unsafe impl Sync for Ctx {}

fn cstr(s: &str) -> CString {
    CString::new(s.replace('\0', "")).unwrap_or_else(|_| CString::new("").unwrap())
}

#[no_mangle]
pub unsafe extern "C" fn puck_pair_run(
    bind_addr: *const c_char,
    port: u16,
    name: *const c_char,
    model: *const c_char,
    out_path: *const c_char,
    ready_cb: Option<
        extern "C" fn(
            *mut c_void,
            *const c_char,
            u16,
            *const *const c_char,
            *const *const c_char,
            usize,
        ),
    >,
    pin_cb: Option<extern "C" fn(*const c_char, *mut c_void)>,
    done_cb: Option<
        extern "C" fn(
            i32,
            *const c_char,
            *const c_char,
            *const c_char,
            *const c_char,
            *const c_char,
            *mut c_void,
        ),
    >,
    ctx: *mut c_void,
) -> i32 {
    if name.is_null() || out_path.is_null() {
        return -1;
    }
    let name = match unsafe { CStr::from_ptr(name) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return -2,
    };
    let model = if model.is_null() {
        "Mac17,7".to_string()
    } else {
        match unsafe { CStr::from_ptr(model) }.to_str() {
            Ok(s) => s.to_string(),
            Err(_) => "Mac17,7".to_string(),
        }
    };
    let out_path = match unsafe { CStr::from_ptr(out_path) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return -2,
    };
    let bind = if bind_addr.is_null() {
        Ipv4Addr::UNSPECIFIED
    } else {
        unsafe { CStr::from_ptr(bind_addr) }
            .to_str()
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(Ipv4Addr::UNSPECIFIED)
    };

    let ctx = Ctx(ctx);
    let rt = match tokio::runtime::Builder::new_multi_thread().enable_all().build() {
        Ok(r) => r,
        Err(_) => return -3,
    };

    let result = rt.block_on(async move {
        let listener = tokio::net::TcpListener::bind((bind, port))
            .await
            .map_err(|e| format!("bind: {e}"))?;
        let bound = listener
            .local_addr()
            .map_err(|e| format!("addr: {e}"))?
            .port();

        let mut pairing_file = RpPairingFile::generate(&name);
        let host_info = PairableHostInfo::generate(&name, &model);
        let host_irk = host_info.alt_irk;
        let service_id = pairing_file.identifier.clone();
        let txt = host_info.mdns_txt_records(&service_id);

        if let Some(cb) = ready_cb {
            let id_c = cstr(&service_id);
            let keys: Vec<CString> = txt.iter().map(|(k, _)| cstr(k)).collect();
            let vals: Vec<CString> = txt.iter().map(|(_, v)| cstr(v)).collect();
            let key_ptrs: Vec<*const c_char> = keys.iter().map(|s| s.as_ptr()).collect();
            let val_ptrs: Vec<*const c_char> = vals.iter().map(|s| s.as_ptr()).collect();
            cb(
                ctx.0,
                id_c.as_ptr(),
                bound,
                key_ptrs.as_ptr(),
                val_ptrs.as_ptr(),
                txt.len(),
            );
        }

        let (stream, _) = listener
            .accept()
            .await
            .map_err(|e| format!("accept: {e}"))?;
        let socket = RpPairingSocket::new_device(stream);
        let mut host = PairableHost::new(socket, host_info);
        host.accept(&mut pairing_file, |pin| {
            let pin_c = cstr(&pin);
            if let Some(cb) = pin_cb {
                cb(pin_c.as_ptr(), ctx.0);
            }
            async {}
        })
        .await
        .map_err(|e| format!("{e}"))?;

        pairing_file
            .write_to_file(&out_path)
            .await
            .map_err(|e| format!("write: {e}"))?;

        let irk = host_irk.iter().map(|x| format!("{x:02x}")).collect::<String>();
        Ok::<_, String>((out_path, pairing_file.identifier.clone(), irk))
    });

    match result {
        Ok((path, ident, irk)) => {
            if let Some(cb) = done_cb {
                let p = cstr(&path);
                let n = cstr("Puck");
                let u = cstr(&ident);
                let i = cstr(&irk);
                cb(
                    1,
                    ptr::null(),
                    p.as_ptr(),
                    n.as_ptr(),
                    u.as_ptr(),
                    i.as_ptr(),
                    ctx.0,
                );
            }
            0
        }
        Err(e) => {
            if let Some(cb) = done_cb {
                let err = cstr(&e);
                cb(
                    0,
                    err.as_ptr(),
                    ptr::null(),
                    ptr::null(),
                    ptr::null(),
                    ptr::null(),
                    ctx.0,
                );
            }
            -4
        }
    }
}
