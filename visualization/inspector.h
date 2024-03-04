#pragma once

/**
 * image buffer is allocated by the user of the inspector
*/
typedef void (*Callback)(void* callbackData, unsigned char** image, int* out_width, int* out_height);

int renderLoop(Callback callback, void* callbackData);
