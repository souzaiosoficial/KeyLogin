#import <UIKit/UIKit.h>
#import <Security/Security.h>

#define SERVER_URL @"http://172.17.75.253:8080/api.php"

%hook AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    BOOL result = %orig;
    [self showKeyAlert];
    return result;
}

%new
- (NSString *)getDeviceID {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *saved = [defaults objectForKey:@"device_id"];
    if (saved) return saved;
    
    // Tentar ler do Keychain
    NSDictionary *query = @{
        (id)kSecClass: (id)kSecClassGenericPassword,
        (id)kSecAttrService: @"com.seuapp.deviceid",
        (id)kSecAttrAccount: @"device_id",
        (id)kSecReturnData: (id)kCFBooleanTrue,
        (id)kSecMatchLimit: (id)kSecMatchLimitOne
    };
    CFDataRef dataRef = NULL;
    OSStatus status = SecItemCopyMatching((CFDictionaryRef)query, (CFTypeRef *)&dataRef);
    if (status == errSecSuccess && dataRef) {
        NSString *deviceID = [[NSString alloc] initWithData:(__bridge NSData *)dataRef encoding:NSUTF8StringEncoding];
        CFRelease(dataRef);
        [defaults setObject:deviceID forKey:@"device_id"];
        [defaults synchronize];
        return deviceID;
    }
    
    // Gerar novo UUID
    NSString *newID = [[NSUUID UUID] UUIDString];
    
    // Salvar no Keychain
    NSData *data = [newID dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *addQuery = @{
        (id)kSecClass: (id)kSecClassGenericPassword,
        (id)kSecAttrService: @"com.seuapp.deviceid",
        (id)kSecAttrAccount: @"device_id",
        (id)kSecValueData: data,
        (id)kSecAttrAccessible: (id)kSecAttrAccessibleAfterFirstUnlock
    };
    SecItemAdd((CFDictionaryRef)addQuery, NULL);
    
    [defaults setObject:newID forKey:@"device_id"];
    [defaults synchronize];
    return newID;
}

%new
- (void)showKeyAlert {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *savedKey = [defaults objectForKey:@"validated_key"];
    NSString *savedDeviceID = [self getDeviceID];
    
    if (savedKey) {
        [self validateKey:savedKey withDeviceID:savedDeviceID completion:^(BOOL success) {
            if (!success) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self promptForKey];
                });
            }
        }];
    } else {
        [self promptForKey];
    }
}

%new
- (void)promptForKey {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Chave de Acesso" message:@"Insira sua chave para liberar o app" preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Chave";
    }];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"Validar" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *key = alert.textFields.firstObject.text;
        if (key.length > 0) {
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            NSString *deviceID = [self getDeviceID];
            [self validateKey:key withDeviceID:deviceID completion:^(BOOL success) {
                if (success) {
                    [defaults setObject:key forKey:@"validated_key"];
                    [defaults synchronize];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"Sucesso" message:@"Chave válida! Aproveite." preferredStyle:UIAlertControllerStyleAlert];
                        [successAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                        [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:successAlert animated:YES completion:nil];
                    });
                } else {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        UIAlertController *failAlert = [UIAlertController alertControllerWithTitle:@"Erro" message:@"Chave inválida ou expirada." preferredStyle:UIAlertControllerStyleAlert];
                        [failAlert addAction:[UIAlertAction actionWithTitle:@"Tentar novamente" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                            [self promptForKey];
                        }]];
                        [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:failAlert animated:YES completion:nil];
                    });
                }
            }];
        } else {
            [self promptForKey];
        }
    }];
    
    [alert addAction:okAction];
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
}

%new
- (void)validateKey:(NSString *)key withDeviceID:(NSString *)deviceID completion:(void (^)(BOOL))completion {
    NSURL *url = [NSURL URLWithString:SERVER_URL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    
    NSString *postString = [NSString stringWithFormat:@"key=%@&device_id=%@", key, deviceID];
    request.HTTPBody = [postString dataUsingEncoding:NSUTF8StringEncoding];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            completion(NO);
            return;
        }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        completion([json[@"success"] boolValue]);
    }];
    [task resume];
}

%end