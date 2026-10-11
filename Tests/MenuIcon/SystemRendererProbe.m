#import <AppKit/AppKit.h>
#import <dlfcn.h>

// Diagnostic executable only. Uses the installed macOS menu renderer in this process,
// without registering/selecting an input source or touching TextInputMenuAgent.
// No private-framework dependency is linked into the product.
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2 || argc > 3) return 2;
        void *framework = dlopen("/System/Library/PrivateFrameworks/TextInputMenuUI.framework/TextInputMenuUI", RTLD_NOW);
        NSImage *(*alignImage)(NSImage *) = dlsym(framework, "createAlignedImage");
        if (!framework || !alignImage) {
            fprintf(stderr, "System renderer unavailable; cannot verify menu geometry on this OS.\n");
            return 77;
        }
        NSImage *source = [[NSImage alloc] initWithContentsOfFile:@(argv[1])];
        if (!source) return 2;
        source.template = YES;
        NSImage *image = alignImage(source);
        if (!image) return 2;
        NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithData:image.TIFFRepresentation];
        if (!bitmap) return 2;
        NSInteger left = bitmap.pixelsWide, right = -1, top = bitmap.pixelsHigh, bottom = -1;
        for (NSInteger y = 0; y < bitmap.pixelsHigh; y++) {
            for (NSInteger x = 0; x < bitmap.pixelsWide; x++) {
                if ([bitmap colorAtX:x y:y].alphaComponent > 200.0 / 255.0) {
                    left = MIN(left, x); right = MAX(right, x);
                    top = MIN(top, y); bottom = MAX(bottom, y);
                }
            }
        }
        CGFloat scaleX = bitmap.pixelsWide / image.size.width;
        CGFloat scaleY = bitmap.pixelsHigh / image.size.height;
        CGFloat width = (right - left + 1) / scaleX;
        CGFloat height = (bottom - top + 1) / scaleY;
        printf("PDF %.1f×%.1f pt → system canvas %.1f×%.1f pt → visible %ld×%ld px (%.1f×%.1f pt)\n",
               source.size.width, source.size.height, image.size.width, image.size.height,
               (long)(right - left + 1), (long)(bottom - top + 1), width, height);
        if (argc == 3) [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
                        writeToFile:@(argv[2]) atomically:YES];
        if (right < left || fabs(width - 22) > 0.5 || fabs(height - 16) > 0.5) {
            fprintf(stderr, "FAIL: actual system image transform does not retain a 22×16 pt badge.\n");
            return 1;
        }
        NSInteger glyphTop = bitmap.pixelsHigh, glyphBottom = -1;
        for (NSInteger y = ceil(scaleY); y < floor(15 * scaleY); y++) {
            for (NSInteger x = ceil(2.5 * scaleX); x < floor(19.5 * scaleX); x++) {
                if ([bitmap colorAtX:x y:y].alphaComponent < 80.0 / 255.0) {
                    glyphTop = MIN(glyphTop, y); glyphBottom = MAX(glyphBottom, y);
                }
            }
        }
        CGFloat glyphHeight = (glyphBottom - glyphTop + 1) / scaleY;
        printf("R letter height: %.1f pt\n", glyphHeight);
        if (glyphBottom < glyphTop || glyphHeight < 7.5 || glyphHeight > 9.0) {
            fprintf(stderr, "FAIL: R letter should match ABC's approximately 8.5 pt cap height.\n");
            return 1;
        }
        puts("PASS: system transform preserves badge size and ABC-scale lettering; installed-menu acceptance remains separate.");
    }
    return 0;
}
