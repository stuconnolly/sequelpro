//
//  SPCSVExporterDelegate.m
//  sequel-pro
//
//  Created by Stuart Connolly (stuconnolly.com) on March 21, 2010.
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

#import "SPCSVExporter.h"
#import "SPCSVExporterDelegate.h"
#import "SPExportFile.h"
#import "SPExportInitializer.h"

@implementation SPExportController (SPCSVExporterDelegate)

- (void)csvExportProcessWillBegin:(SPCSVExporter *)exporter
{
	[exportProgressText displayIfNeeded];

	[exportProgressIndicator setIndeterminate:YES];
	[exportProgressIndicator setUsesThreadedAnimation:YES];
	[exportProgressIndicator startAnimation:self];

	// Only update the progress text if this is a table export
	if (exportSource == SPTableExport) {
		// Update the current table export index
		currentTableExportIndex = (exportTableCount - [exporters count]);

		[exportProgressText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Table %lu of %lu (%@): Fetching data...", @"export label showing that the app is fetching data for a specific table"), currentTableExportIndex, exportTableCount, [exporter csvTableName]]];
	}
	else {
		[exportProgressText setStringValue:NSLocalizedString(@"Fetching data...", @"export label showing that the app is fetching data")];
	}

	[exportProgressText displayIfNeeded];
}

- (void)csvExportProcessComplete:(SPCSVExporter *)exporter
{		
	NSUInteger exportCount = [exporters count];
	
	// If required add the next exporter to the operation queue
	if ((exportCount > 0) && (exportSource == SPTableExport)) {
			
		// If we're only exporting to a single file then write a header for the next table
		if (!exportToMultipleFiles) {
			
			// If we're exporting multiple tables to a single file then append some space and the next table's
			// name, but only if there is at least 2 exportes left.
			[[exporter exportOutputFile] writeData:[[NSString stringWithFormat:@"%@%@%@ %@%@%@", 
														   [exporter csvLineEndingString], 
														   [exporter csvLineEndingString],
														   NSLocalizedString(@"Table", @"csv export table heading"),
														   [(SPCSVExporter *)[exporters objectAtIndex:0] csvTableName],
														   [exporter csvLineEndingString],
														   [exporter csvLineEndingString]] dataUsingEncoding:[exporter exportOutputEncoding]]];
		}
		// Otherwise close the file handle of the exporter that just finished 
		// ensuring it's data is written to disk.
		else {
			[[exporter exportOutputFile] close];
		}
		
		[operationQueue addOperation:[exporters objectAtIndex:0]];
		
		// Remove the exporter we just added to the operation queue from our list of exporters 
		// so we know it's already been done.
		[exporters removeObjectAtIndex:0];
	}
	// Otherwise if the exporter list is empty, close the progress sheet
	else {
		// Close the last exporter's file handle
		[[exporter exportOutputFile] close];

		[self exportEnded];
	}
}

- (void)csvExportProcessWillBeginWritingData:(SPCSVExporter *)exporter
{
	// Only update the progress text if this is a table export
	if (exportSource == SPTableExport) {
		[exportProgressText setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Table %lu of %lu (%@): Writing data...", @"export label showing app if writing data for a specific table"), currentTableExportIndex, exportTableCount, [exporter csvTableName]]];
	}
	else {
		[exportProgressText setStringValue:NSLocalizedString(@"Writing data...", @"export label showing app is writing data")];
	}

	[exportProgressText displayIfNeeded];

	[exportProgressIndicator stopAnimation:self];
	[exportProgressIndicator setUsesThreadedAnimation:NO];
	[exportProgressIndicator setIndeterminate:NO];
	[exportProgressIndicator setDoubleValue:0];
}

- (void)csvExportProcessProgressUpdated:(SPCSVExporter *)exporter
{
	[exportProgressIndicator setDoubleValue:[exporter exportProgressValue]];
}

@end
