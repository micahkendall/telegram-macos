#import <Foundation/Foundation.h>
#import <MtProtoKit/MTApiEnvironment.h>
#import <MtProtoKit/MTMacOSClientInfo.h>

int main(void) {
    @autoreleasepool {
        NSBundle *bundle = NSBundle.mainBundle;
        NSDictionary *profile = bundle.infoDictionary[@"TGMacClientProfile"];
        MTApiEnvironment *environment = [[MTApiEnvironment alloc] initWithDeviceModelName:nil];
        environment.apiId = [profile[@"api_id"] intValue];
        environment.layer = @(TELEGRAM_API_LAYER);
        environment.langPack = profile[@"language_category"];
        environment = [environment withUpdatedLangPackCode:@"en"];
        NSData *appData = MTMacOSClientAppData(bundle);
        if (appData == nil) {
            return 1;
        }
        NSData *params = [@"test-native-params" dataUsingEncoding:NSUTF8StringEncoding];
        environment = [environment withUpdatedSystemCode:params];
        MTApiEnvironment *copied = [environment withUpdatedNetworkSettings:[[MTNetworkSettings alloc] initWithReducedBackupDiscoveryTimeout:false]];
        copied = [copied withUpdatedSocksProxySettings:nil];
        if (![environment.deviceModel isEqualToString:copied.deviceModel] ||
            ![environment.systemVersion isEqualToString:copied.systemVersion] ||
            ![environment.appVersion isEqualToString:copied.appVersion] ||
            ![environment.systemCode isEqualToData:copied.systemCode] ||
            ![environment.apiInitializationHash isEqualToString:copied.apiInitializationHash]) {
            return 2;
        }
        NSDictionary *result = @{
            @"api_id": @(environment.apiId),
            @"layer": environment.layer,
            @"device_model": environment.deviceModel ?: @"",
            @"system_version": environment.systemVersion ?: @"",
            @"app_version": environment.appVersion ?: @"",
            @"system_lang_code": environment.systemLangCode ?: @"",
            @"lang_pack": environment.langPack ?: @"",
            @"lang_code": environment.langPackCode ?: @"",
            @"params": [NSJSONSerialization JSONObjectWithData:appData options:0 error:NULL],
            @"copy_preserves_environment": @YES
        };
        NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingSortedKeys error:NULL];
        fwrite(json.bytes, 1, json.length, stdout);
        fputc('\n', stdout);
    }
    return 0;
}
