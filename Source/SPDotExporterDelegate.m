//
//  SPDotExporterDelegate.m
//  sequel-pro
//
//  Created by Stuart Connolly (stuconnolly.com) on April 17, 2010.
//  Copyright (c) 2010 Stuart Connolly. All rights reserved.
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

#import "SPDotExporterDelegate.h"
#import "SPDotExporter.h"
#import "SPExportInitializer.h"

@implementation SPExportController (SPDotExporterDelegate)

- (void)dotExportProcessWillBegin:(SPDotExporter *)exporter
{
	[exportProgressTitle setStringValue:NSLocalizedString(@"Exporting Dot File", @"text showing that the application is exporting a Dot file")];
	[exportProgressText setStringValue:NSLocalizedString(@"Dumping...", @"text showing that app is writing dump")];

	[exportProgressTitle displayIfNeeded];
	[exportProgressText displayIfNeeded];
	[exportProgressIndicator stopAnimation:self];
	[exportProgressIndicator setIndeterminate:NO];
}

- (void)dotExportProcessComplete:(SPDotExporter *)exporter
{
	[self exportEnded];
}

- (void)dotExportProcessProgressUpdated:(SPDotExporter *)exporter
{
	[exportProgressIndicator setDoubleValue:[exporter exportProgressValue]];
}

- (void)dotExportProcessWillBeginFetchingData:(SPDotExporter *)exporter forTableWithIndex:(NSUInteger)tableIndex
{
	// Update the current table export index
	currentTableExportIndex = tableIndex;
	
	[exportProgressText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Table %lu of %lu (%@): Fetching data...", @"export label showing that the app is fetching data for a specific table"), currentTableExportIndex, exportTableCount, [exporter dotExportCurrentTable]]];
	
	[exportProgressText displayIfNeeded];
}

- (void)dotExportProcessWillBeginFetchingRelationsData:(SPDotExporter *)exporter
{
	[exportProgressText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Table %lu of %lu (%@): Fetching relations data...", @"export label showing app is fetching relations data for a specific table"), currentTableExportIndex, exportTableCount, [exporter dotExportCurrentTable]]];
	
	[exportProgressText displayIfNeeded];
	[exportProgressIndicator setIndeterminate:YES];
	[exportProgressIndicator setUsesThreadedAnimation:YES];
	[exportProgressIndicator startAnimation:self];
}

@end
