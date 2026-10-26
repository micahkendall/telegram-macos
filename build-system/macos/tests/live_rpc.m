#import <Foundation/Foundation.h>
#import <MtProtoKit/MTApiEnvironment.h>
#import <MtProtoKit/MTMacOSClientInfo.h>
#define MTBuffer MTFFIBuffer
#define MTRequest MTFFIRequest
#include "mtproto_engine.h"
#undef MTBuffer
#undef MTRequest

@interface ProbeState : NSObject
@property (nonatomic, strong) NSCondition *condition;
@property (nonatomic, strong) NSMutableDictionary *responses;
@property (nonatomic, strong) NSMutableArray *failures;
@property (nonatomic) BOOL permanentKeyCreated;
@property (nonatomic) BOOL temporaryKeyCreated;
@property (nonatomic) BOOL temporaryKeyBound;
@property (nonatomic) BOOL initStored;
@end
@implementation ProbeState
@end

static MTString ProbeString(NSString *value) {
    const char *data = value.UTF8String;
    return (MTString){data, strlen(data)};
}

static void ProbeInteger(NSMutableData *data, uint32_t value) {
    uint32_t little = CFSwapInt32HostToLittle(value);
    [data appendBytes:&little length:4];
}

static void ProbeTLString(NSMutableData *data, NSString *value) {
    NSData *bytes = [value dataUsingEncoding:NSUTF8StringEncoding];
    NSCAssert(bytes.length < 254, @"Probe metadata strings must fit the short TL encoding");
    uint8_t size = (uint8_t)bytes.length;
    [data appendBytes:&size length:1];
    [data appendData:bytes];
    uint8_t zero = 0;
    while (data.length % 4 != 0) {
        [data appendBytes:&zero length:1];
    }
}

static NSData *ProbeParams(NSData *json) {
    NSDictionary *object = [NSJSONSerialization JSONObjectWithData:json options:0 error:NULL];
    NSMutableData *data = [NSMutableData data];
    ProbeInteger(data, 0x99c1d49d);
    ProbeInteger(data, 0x1cb5c415);
    ProbeInteger(data, (uint32_t)object.count);
    for (NSString *key in [object.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        ProbeInteger(data, 0xc0de1bd9);
        ProbeTLString(data, key);
        ProbeInteger(data, 0xb71e767a);
        ProbeTLString(data, object[key]);
    }
    return data;
}

static void ProbeEvent(void *context, MTSessionHandle session, const MTEvent *event) {
    @autoreleasepool {
        ProbeState *state = (__bridge ProbeState *)context;
        [state.condition lock];
        switch (event->kind) {
            case MTEventKindCompleted: {
                uint32_t constructor = 0;
                size_t length = mt_buffer_length(event->payload);
                if (length >= 4) {
                    memcpy(&constructor, mt_buffer_data(event->payload), 4);
                    constructor = CFSwapInt32LittleToHost(constructor);
                }
                state.responses[[NSString stringWithFormat:@"%llu", (unsigned long long)event->request_id]] = @{@"constructor": [NSString stringWithFormat:@"%08x", constructor], @"bytes": @(length)};
                break;
            }
            case MTEventKindFailed:
            case MTEventKindAuthKeyCreationFailed:
            case MTEventKindTemporaryKeyBindFailed: {
                NSString *text = [[NSString alloc] initWithBytes:event->text.data length:event->text.length encoding:NSUTF8StringEncoding] ?: @"";
                [state.failures addObject:@{@"kind": @(event->kind), @"code": @(event->code), @"message": text}];
                break;
            }
            case MTEventKindAuthKeyCreated:
                state.permanentKeyCreated |= (event->flags & MTAuthKeyCreatedPermanent) != 0;
                state.temporaryKeyCreated |= (event->flags & MTAuthKeyCreatedTemporary) != 0;
                break;
            case MTEventKindTemporaryKeyBound:
                state.temporaryKeyBound = YES;
                break;
            case MTEventKindInitHashStored:
                state.initStored = YES;
                break;
            default:
                break;
        }
        [state.condition signal];
        [state.condition unlock];
        if (event->payload != NULL) {
            mt_buffer_free(event->payload);
        }
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3 && argc != 4) {
            return 2;
        }
        BOOL pfs = strcmp(argv[2], "pfs") == 0;
        BOOL qr = argc == 4 && strcmp(argv[3], "qr") == 0;
        NSString *pem = [NSString stringWithContentsOfFile:[NSString stringWithUTF8String:argv[1]] encoding:NSUTF8StringEncoding error:NULL];
        if (pem == nil) {
            return 2;
        }
        NSBundle *bundle = NSBundle.mainBundle;
        NSDictionary *profile = bundle.infoDictionary[@"TGMacClientProfile"];
        MTApiEnvironment *api = [[MTApiEnvironment alloc] initWithDeviceModelName:nil];
        api.apiId = [profile[@"api_id"] intValue];
        api.layer = @(TELEGRAM_API_LAYER);
        api.langPack = profile[@"language_category"];
        api = [api withUpdatedLangPackCode:@"en"];
        NSData *params = ProbeParams(MTMacOSClientAppData(bundle));
        api = [api withUpdatedSystemCode:params];
        MTEnvironment environment = {0};
        environment.layer = TELEGRAM_API_LAYER;
        environment.api_id = api.apiId;
        environment.device_model = ProbeString(api.deviceModel);
        environment.system_version = ProbeString(api.systemVersion);
        environment.app_version = ProbeString(api.appVersion);
        environment.system_lang_code = ProbeString(api.systemLangCode);
        environment.lang_pack = ProbeString(api.langPack);
        environment.lang_code = ProbeString(api.langPackCode);
        environment.has_params = 1;
        environment.params = (MTBytes){params.bytes, params.length};
        environment.init_hash = ProbeString(api.apiInitializationHash);

        ProbeState *state = [[ProbeState alloc] init];
        state.condition = [[NSCondition alloc] init];
        state.responses = [NSMutableDictionary dictionary];
        state.failures = [NSMutableArray array];
        MTEngine *engine = mt_engine_create(2, (__bridge void *)state, ProbeEvent, NULL);
        mt_engine_set_network_available(engine, 1);
        MTAddress addresses[] = {{ProbeString(@"149.154.167.50"), 443, {NULL, 0}}, {ProbeString(@"149.154.167.51"), 443, {NULL, 0}}};
        MTString publicKey = ProbeString(pem);
        MTSessionSetup setup = {0};
        setup.datacenter_id = 2;
        setup.obfuscation_dc_id = 2;
        setup.role = MTSessionRoleMain;
        setup.framing = MTFramingAbridged;
        setup.addresses = addresses;
        setup.address_count = 2;
        setup.generate_key = pfs ? 0 : 1;
        setup.public_keys_pem = &publicKey;
        setup.public_key_count = 1;
        setup.environment = &environment;
        setup.online = 1;
        setup.keep_connected = 1;
        setup.request_timeout = 15.0;
        setup.pfs_lifetime = pfs ? 86400 : 0;
        setup.pfs_make_permanent_key = pfs ? 1 : 0;
        MTSessionHandle session = mt_session_create(engine, &setup);
        mt_session_set_transport(engine, session, MTTransportAuto, 80);
        uint32_t methods[] = {CFSwapInt32HostToLittle(0x1fb33026), CFSwapInt32HostToLittle(0xc4f9186b)};
        for (NSUInteger index = 0; index < 2; index++) {
            MTFFIRequest request = {0};
            request.id = index + 1;
            request.body = (MTBytes){(const uint8_t *)&methods[index], 4};
            request.flags = MTRequestFlagTimeoutTimer;
            mt_session_send(engine, session, &request);
        }
        if (qr) {
            NSMutableData *body = [NSMutableData data];
            ProbeInteger(body, 0xb7e085fe);
            ProbeInteger(body, (uint32_t)api.apiId);
            ProbeTLString(body, profile[@"api_hash"]);
            ProbeInteger(body, 0x1cb5c415);
            ProbeInteger(body, 0);
            MTFFIRequest request = {0};
            request.id = 3;
            request.body = (MTBytes){body.bytes, body.length};
            request.flags = MTRequestFlagTimeoutTimer;
            mt_session_send(engine, session, &request);
        }
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:40.0];
        [state.condition lock];
        while (state.responses.count < (qr ? 3 : 2) && state.failures.count == 0) {
            if (![state.condition waitUntilDate:deadline]) {
                break;
            }
        }
        [state.condition unlock];
        mt_engine_destroy(engine);
        BOOL success = state.failures.count == 0 && state.permanentKeyCreated &&
            [state.responses[@"1"][@"constructor"] isEqualToString:@"8e1a1775"] &&
            [state.responses[@"2"][@"constructor"] isEqualToString:@"cc1a241e"] &&
            (!pfs || (state.temporaryKeyCreated && state.temporaryKeyBound)) &&
            (!qr || [state.responses[@"3"][@"constructor"] isEqualToString:@"629f1980"]);
        NSDictionary *report = @{
            @"success": @(success), @"pfs": @(pfs), @"qr_token_requested": @(qr), @"permanent_key_created": @(state.permanentKeyCreated),
            @"temporary_key_created": @(state.temporaryKeyCreated), @"temporary_key_bound": @(state.temporaryKeyBound),
            @"init_stored": @(state.initStored), @"responses": state.responses, @"failures": state.failures
        };
        NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingSortedKeys error:NULL];
        fwrite(json.bytes, 1, json.length, stdout);
        fputc('\n', stdout);
        return success ? 0 : 1;
    }
}
