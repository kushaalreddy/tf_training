// Copyright 2022 The TensorFlow Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import "TFLRingBuffer.h"
#import "TFLAudioError.h"
#import "TFLUtils.h"

@implementation TFLRingBuffer {
  NSInteger nextIndex;
  TFLFloatBuffer *_buffer;
}

- (instancetype)initWithBufferSize:(NSInteger)size {
  self = [self init];
  if (self) {
    _buffer = [[TFLFloatBuffer alloc] initWithSize:size];
  }
  return self;
}

- (BOOL)loadBuffer:(TFLFloatBuffer *)sourceBuffer
            offset:(NSUInteger)offset
              size:(NSUInteger)size
             error:(NSError **)error {
  NSInteger sizeToCopy = size;
  NSInteger newOffset = offset;

  if (offset + size > sourceBuffer.size) {
    [TFLUtils createCustomError:error
                       withCode:TFLAudioErrorCodeInvalidArgumentError
                    description:@"offset + size exceeds the maximum size of the source buffer."];
    return NO;
  }

  // Length is greater than buffer size, then modify size and offset to
  // keep most recent data in the sourceBuffer.
  if (size >= _buffer.size) {
    sizeToCopy = _buffer.size;
    newOffset = offset + (size - _buffer.size);
  }

  // If the new nextIndex + sizeToCopy is smaller than the size of the ring buffer directly
  // copy all elements to the end of the ring buffer.
  if (nextIndex + sizeToCopy < _buffer.size) {
    memcpy(_buffer.data + nextIndex, sourceBuffer.data + newOffset, sizeof(float) * sizeToCopy);
  } else {
    // If
    NSInteger endChunkSize = _buffer.size - nextIndex;
    memcpy(_buffer.data + nextIndex, sourceBuffer.data + newOffset, sizeof(float) * endChunkSize);

    NSInteger startChunkSize = sizeToCopy - endChunkSize;
    memcpy(_buffer.data, sourceBuffer.data + newOffset + endChunkSize,
           sizeof(float) * startChunkSize);
  }

  nextIndex = (nextIndex + sizeToCopy) % _buffer.size;

  return YES;
}

- (TFLFloatBuffer *)floatBuffer {
  return [self floatBufferWithOffset:0 size:[self size]];
}

- (nullable TFLFloatBuffer *)floatBufferWithOffset:(NSUInteger)offset size:(NSUInteger)size {
  if (offset + size > _buffer.size) {
    return nil;
  }

  // Return buffer in correct order.
  // Compute offset in flat ring buffer array considering warping.
  NSUInteger correctOffset = (nextIndex + offset) % _buffer.size;

  TFLFloatBuffer *floatBuffer = [[TFLFloatBuffer alloc] initWithSize:size];

  // If no; elements to be copied are within the end of the flat ring buffer.
  if ((correctOffset + size) <= _buffer.size) {
    memcpy(floatBuffer.data, _buffer.data + correctOffset, sizeof(float) * size);
  } else {
    // If no; elements to be copied warps around to the beginning of the ring buffer.
    // Copy the chunk starting at ringBuffer[nextIndex + offset : size] to
    // beginning of the result array.
    NSInteger endChunkSize = _buffer.size - correctOffset;
    memcpy(floatBuffer.data, _buffer.data + correctOffset, sizeof(float) * endChunkSize);

    // Next copy the chunk starting at ringBuffer[0 : size - endChunkSize] to the result array.
    NSInteger firstChunkSize = size - endChunkSize;
    memcpy(floatBuffer.data + endChunkSize, _buffer.data, sizeof(float) * firstChunkSize);
  }

  return floatBuffer;
}

- (NSUInteger)size {
  return _buffer.size;
}

@end