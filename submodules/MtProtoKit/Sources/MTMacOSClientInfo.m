#import <MtProtoKit/MTMacOSClientInfo.h>
#import <TargetConditionals.h>
#import <sys/sysctl.h>

#if TARGET_OS_MACCATALYST
#import <spawn.h>
#import <fcntl.h>
#import <poll.h>
#import <signal.h>
#import <sys/wait.h>
#import <unistd.h>
extern char **environ;

static NSString *MTMacSysctlString(const char *name) {
    size_t size = 0;
    if (sysctlbyname(name, NULL, &size, NULL, 0) != 0 || size == 0) {
        return @"";
    }
    NSMutableData *data = [NSMutableData dataWithLength:size];
    if (sysctlbyname(name, data.mutableBytes, &size, NULL, 0) != 0) {
        return @"";
    }
    return [[NSString alloc] initWithBytes:data.bytes length:strnlen(data.bytes, size) encoding:NSUTF8StringEncoding] ?: @"";
}

static NSString *MTMacProfilerModel(void) {
    int descriptors[2];
    if (pipe(descriptors) != 0) {
        return nil;
    }
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDOUT_FILENO);
    posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addclose(&actions, descriptors[0]);
    posix_spawn_file_actions_addclose(&actions, descriptors[1]);
    char *arguments[] = {"/usr/sbin/system_profiler", "-json", "SPHardwareDataType", "-detailLevel", "mini", NULL};
    pid_t child;
    int result = posix_spawn(&child, arguments[0], &actions, NULL, arguments, environ);
    posix_spawn_file_actions_destroy(&actions);
    close(descriptors[1]);
    if (result != 0) {
        close(descriptors[0]);
        return nil;
    }
    NSMutableData *data = [NSMutableData data];
    NSTimeInterval deadline = [NSDate timeIntervalSinceReferenceDate] + 5.0;
    BOOL ended = NO;
    while ([NSDate timeIntervalSinceReferenceDate] < deadline && data.length < 65536) {
        struct pollfd descriptor = {descriptors[0], POLLIN, 0};
        if (poll(&descriptor, 1, 100) < 0) {
            break;
        }
        if (descriptor.revents & (POLLIN | POLLHUP)) {
            char bytes[4096];
            ssize_t count = read(descriptors[0], bytes, sizeof(bytes));
            if (count <= 0) {
                ended = YES;
                break;
            }
            [data appendBytes:bytes length:(NSUInteger)count];
        }
    }
    close(descriptors[0]);
    if (!ended) {
        kill(child, SIGKILL);
    }
    waitpid(child, NULL, 0);
    if (!ended) {
        return nil;
    }
    NSDictionary *document = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    NSDictionary *hardware = [document[@"SPHardwareDataType"] firstObject];
    NSString *machine = hardware[@"machine_name"];
    NSString *chip = hardware[@"chip_type"];
    if (![machine isKindOfClass:NSString.class] || machine.length == 0) {
        return nil;
    }
    if ([chip isKindOfClass:NSString.class] && [chip hasPrefix:@"Apple "]) {
        return [machine stringByAppendingString:[chip substringFromIndex:5]];
    }
    return machine;
}
#endif

NSString *MTMacOSClientDeviceModel(void) {
    static NSString *model;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
#if TARGET_OS_MACCATALYST
        model = MTMacProfilerModel();
        if (model == nil) {
            NSString *identifier = MTMacSysctlString("hw.model");
            NSMutableArray<NSString *> *words = [NSMutableArray array];
            NSMutableString *word = [NSMutableString string];
            for (NSUInteger index = 0; index < identifier.length; index++) {
                unichar character = [identifier characterAtIndex:index];
                if (![[NSCharacterSet letterCharacterSet] characterIsMember:character]) {
                    continue;
                }
                if ([[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:character] && word.length != 0) {
                    [words addObject:[word copy]];
                    [word setString:@""];
                }
                [word appendFormat:@"%C", character];
            }
            if (word.length != 0) {
                [words addObject:word];
            }
            NSMutableString *parsed = [NSMutableString string];
            for (NSString *part in words) {
                if (parsed.length != 0 && ![part isEqualToString:@"Mac"] && ![part isEqualToString:@"Book"]) {
                    [parsed appendString:@" "];
                }
                [parsed appendString:part];
            }
            model = [parsed copy];
        }
#else
        model = @"";
#endif
    });
    return model;
}

NSString *MTMacOSClientSystemVersion(void) {
#if TARGET_OS_MACCATALYST
    NSString *version = MTMacSysctlString("kern.osproductversion");
    if (version.length != 0) {
        return version;
    }
#endif
    return [[[NSProcessInfo.processInfo operatingSystemVersionString] componentsSeparatedByString:@" "] objectAtIndex:1];
}

NSData *MTMacOSClientAppData(NSBundle *bundle) {
    NSDictionary *profile = bundle.infoDictionary[@"TGMacClientProfile"];
    if (![profile isKindOfClass:NSDictionary.class]) {
        return nil;
    }
    NSString *identifier = profile[@"network_bundle_id"];
    NSString *fingerprint = profile[@"signing_certificate_sha1"];
    if (![identifier isKindOfClass:NSString.class] || ![fingerprint isKindOfClass:NSString.class]) {
        return nil;
    }
    return [NSJSONSerialization dataWithJSONObject:@{@"bundleId": identifier, @"data": fingerprint} options:0 error:NULL];
}
