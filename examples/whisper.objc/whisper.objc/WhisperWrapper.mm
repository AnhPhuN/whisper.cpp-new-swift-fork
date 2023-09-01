#include "whisper.h"
#import "WhisperWrapper.h"

// WhisperWrapper.mm
//#include "whisper.cpp"

@implementation WhisperWrapper

- (whisper_context *)whisper_init_from_file:(const char *)pathModel {
    return whisper_init_from_file(pathModel);
}


@end
