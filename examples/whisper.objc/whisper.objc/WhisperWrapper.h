//
//  WhisperWrapper.h
//  whisper.objc
//
//  Created by Phu Nguyen on 8/25/23.
//

#import <Foundation/Foundation.h>

@interface WhisperWrapper : NSObject

- (struct whisper_context *)whisper_init_from_file:(const char *)pathModel;

@end
