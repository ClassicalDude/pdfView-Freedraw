# Compiling <code>PDFFreedrawGestureRecognizer</code> from Source

Including the source code for <code>PDFFreedrawGestureRecognizer</code> in your project is not trivial, and therefore the recommended use is through the pre-compiled xcframework (consult the [README](README.md#installation) file). If you do wish to compile it from source into a Swift project, please follow these steps:

## 1. Get the Supporting Libraries
<code>PDFFreedrawGestureRecognizer</code>'s eraser and oval-snapping depend on Adam Wulf's [ClippingBezier library](https://github.com/adamwulf/ClippingBezier), which in turn depends on a CocoaPods installation of his [PerformanceBezier](https://github.com/adamwulf/PerformanceBezier).

Start by downloading and setting up ClippingBezier according to its author's instructions.

### Important Steps:
- Don't forget to run <code>pod install</code> from ClippingBezier's root directory, so that it installs the PerformanceBezier dependency.
- In Xcode, open the xcworkspace file rather than the xcodeproj file.
- You may have to use the "Manage Scheme" dialog and add a check mark next to the ClippingBezier framework for it to show as a target.
- Do not forget to add <code>-ObjC++ -lstdc++</code> to the Other Linker Flags of your target's Build Settings.
- If you want to build for Mac Catalyst, go to the General tab of the target's settings, and check macOS 10.15 under "Deployment Info".
- Build the project 3 times: with an "Any iOS Device" destination, with an "Any Mac (Intel)" destination (this one is for Mac Catalyst), and with your choice of a simulator destination.

Sadly, I was not able to successfully merge ClippingBezier as a secondary project into my own code - it failed to compile unless accessed from its xcworkspace, which you cannot import into a different project. The steps described above produced two compiled binaries: <code>libClippingBezier.a</code> and <code>libPerformanceBezier.a</code>. They were compiled three times, once for every destination. I extracted them from my <code>~/Library/Developer/Xcode/DerivedData/ClippingBezier.../Build/Products/$ARCH/ClippingBezier</code> (similar path for <code>PerformanceBezier</code>, just change the last path component) and embedded them as static libraries in my project.

This meant, of course, that I had to swap these two binaries every time I changed destination devices in my own project. If you don't plan to use Mac Catalyst, you can solve this by merging the physical device (iOS) binaries and the simulator binaries into fat binaries by using <code>lipo -create /PATH/TO/iOS/libClippingBezier.a /PATH/TO/SIMULATOR/libClippingBezier.a -output /PATH/TO/COMBINED/libClippingBezier.a</code> (do the same for <code>libPerformanceBezier</code>).

Mac Catalyst cannot be combined into a fat framework, since it shares architecture with the simulator, and Xcode refuses to use the same binary for these two destinations. This is one reason why xcframeworks came to being. I ended up creating an xcframework for the entire <code>PDFFreedrawGestureRecognizer</code> class, including its dependecies. This also proved to be a lengthy and tedious process, and will not be covered here. Let me know if it essential for you to get help with this matter.

For now, let's continue with embedding the static fat libraries into our project, assuming that you do not require Mac Catalyst.

## 2. Embed <code>libClippingBezier.a</code> and <code>libPerformanceBezier.a</code>
1. Copy these two files into their own folder, and drag that folder into your project. Choose "Copy If Necessary" in the prompt. Go to the Build Phases tab of your target, expand "Link Binary With Libraries", click the + button, choose "Add Others" at the bottom and then "Add Files". Find the folder with the two binaries and select them both.

2. Use the finder to create another folder, named "Headers". Create two subfolders in it, named "ClippingBezier" and "PerformanceBezier". Now go to the ClippingBezier folder within the original ClippingBezier project, and copy all of the header files (.h and .hxx) to your newly created Headers/ClippingBezier folder. Next, go to Pods/PerformanceBezier/PerformanceBezier and do the same to the Headers/PerformanceBezier folder.

3. Go to your target's Build Settings and find the "Library Search Paths" entry. Type the path to the two binary files. Make sure you do NOT make it recursive, and remember that you can use $(PROJECT_DIR) to get the root of your project.

4. Next to the previous entry, you'll find "Header Search Paths". Add the path to the Headers folder (without the subfolders).

5. ClippingBezier and PerformanceBezier are Objective-C libraries. Getting them to work with a Swift project requires the use of a bridging header and a prefix file. From File->New->File choose to create a new header file. Name it YOUR-PROJECT-NAME-Bridging-Header.h, and put it into the root of your project. Its content should be:
```
#import <PerformanceBezier/PerformanceBezier.h>
#import <ClippingBezier/ClippingBezier.h>
```
Now, from File->New->File choose to create a new pch file. Name it YOUR-PROJECT-NAME-Prefix.pch, and in the block between <code>#define...</code> and <code>#endif...</code> add the same two lines as above.

6. Go back to the target's Build Settings, find Objective-C Bridging Header and add the path to your bridging header. Find the Prefix Header entry and add the path to the prefix pch file.

7. Still in Build Settings, find Other Linker Flags and add <code>-ObjC++ -lstdc++</code>.

That should be it for the dependencies.

## 3. Add the necessary files for <code>PDFFreedrawGestureRecognizer</code>

The files required for the class are <code>PDFFreedrawGestureRecognizer.swift</code>, <code>FreedrawExtensions.swift</code> and <code>UIBezierPath+</code>. Drag them into your project and make sure you add them to your target.

If everything worked correctly, the class <code>PDFFreedrawGestureRecognizer.swift</code> should now be accessible from anywhere in your project, and it should be able to compile.

