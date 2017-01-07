//
//  SPExportSettingsPersistence.h
//  sequel-pro
//
//  Created by Max Lohrmann on 09.10.15.
//  Copyright (c) 2015 Max Lohrmann. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//
//  More info at <https://github.com/sequelpro/sequelpro>

#import <Foundation/Foundation.h>
#import "SPExportController.h"

@interface SPExportController (SPExportSettingsPersistence)

- (IBAction)exportCurrentSettings:(id)sender;
- (IBAction)importCurrentSettings:(id)sender;

/**
 * @return The current settings as a dictionary which can be serialized
 */
- (NSDictionary *)currentSettingsAsDictionary;

/** Overwrite current export settings with those defined in dict
 * @param dict The new settings to apply (passing nil is an error.)
 * @param err  Errors while applying (will mostly be about invalid format, type)
 *             Can pass NULL, if not interested in details.
 *             Will NOT be changed unless the method also returns NO
 * @return success
 */
- (BOOL)applySettingsFromDictionary:(NSDictionary *)dict error:(NSError **)err;

/**
 * @return A serialized form of the "custom filename" field
 */
- (NSArray *)currentCustomFilenameAsArray;

/**
 * @param tokenList A serialized form of the "custom filename" field
 * @see currentCustomFilenameAsArray
 */
- (void)setCustomFilenameFromArray:(NSArray *)tokenList;

@end
