//
//  SPConnectionDelegate.m
//  sequel-pro
//
//  Created by Stuart Connolly (stuconnolly.com) on October 26, 2010.
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

#import "SPTableStructureDelegate.h"
#import "SPAlertSheets.h"
#import "SPDatabaseData.h"
#import "SPDatabaseViewController.h"
#import "SPTableData.h"
#import "SPTableView.h"
#import "SPTableFieldValidation.h"
#import "SPTableStructureLoading.h"
#import "SPServerSupport.h"
#import "SPTablesList.h"
#import "SPPillAttachmentCell.h"
#import "SPIdMenu.h"
#import "SPComboBoxCell.h"

#import <SPMySQL/SPMySQL.h>

struct _cmpMap {
	NSString *title; // the title of the "pill"
	NSString *tooltipPart; // the tooltip of the menuitem
	NSString *cmpWith; // the string to match against
};

/**
 * This function will compare the representedObject of every item in menu against
 * every map->cmpWith. If they match it will append a pill-like (similar to a TokenFieldCell's token)
 * element labelled map->title to the menu item's title. If map->tooltipPart is set,
 * it will also be added to the menu item's tooltip.
 *
 * This is used with the encoding/collation popup menus to add visual indicators for the
 * table-level and default encoding/collation.
 */
static void _BuildMenuWithPills(NSMenu *menu,struct _cmpMap *map,size_t mapEntries);

@interface SPTableStructure (PrivateAPI)

- (void)sheetDidEnd:(id)sheet returnCode:(NSInteger)returnCode contextInfo:(NSString *)contextInfo;
- (NSString *)_buildPartialColumnDefinitionString:(NSDictionary *)theRow;

- (void)_displayFieldTypeHelpIfPossible:(SPComboBoxCell *)cell;

@end

@implementation SPTableStructure (SPTableStructureDelegate)

#pragma mark -
#pragma mark Table view datasource methods

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [tableFields count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	// Return a placeholder if the table is reloading
	if ((NSUInteger)rowIndex >= [tableFields count]) return @"...";

	NSDictionary *rowData = NSArrayObjectAtIndex(tableFields, rowIndex);
	
	if ([[tableColumn identifier] isEqualToString:@"collation"]) {
		NSString *tableEncoding = [tableDataInstance tableEncoding];
		NSString *columnEncoding = [rowData objectForKey:@"encodingName"];
		NSString *columnCollation = [rowData objectForKey:@"collationName"]; // loadTable: has already inferred it, if not set explicit

#warning Building the collation menu here is a big performance hog. This should be done in menuNeedsUpdate: below!
		NSPopUpButtonCell *collationCell = [tableColumn dataCell];
		[collationCell removeAllItems];
		[collationCell addItemWithTitle:@"dummy"];
		//copy the default style of menu items and add gray color for default item
		NSMutableDictionary *menuAttrs = [NSMutableDictionary dictionaryWithDictionary:[[collationCell attributedTitle] attributesAtIndex:0 effectiveRange:NULL]];
		[menuAttrs setObject:[NSColor lightGrayColor] forKey:NSForegroundColorAttributeName];
		[[collationCell lastItem] setTitle:@""];

		//if this is not set the column either has no encoding (numeric etc.) or retrieval failed. Either way we can't provide collations
		if([columnEncoding length]) {
			collations = [databaseDataInstance getDatabaseCollationsForEncoding:columnEncoding];

			if ([collations count] > 0) {
				NSString *tableCollation = [[tableDataInstance statusValues] objectForKey:@"Collation"];

				if (![tableCollation length]) {
					tableCollation = [databaseDataInstance getDefaultCollationForEncoding:tableEncoding];
				}

				BOOL columnUsesTableDefaultEncoding = ([columnEncoding isEqualToString:tableEncoding]);
				// Populate collation popup button
				for (NSDictionary *collation in collations)
				{
					NSString *collationName = [collation objectForKey:@"COLLATION_NAME"];

					[collationCell addItemWithTitle:collationName];
					NSMenuItem *item = [collationCell lastItem];
					[item setRepresentedObject:collationName];

					// If this matches the table's collation, draw in gray
					if (columnUsesTableDefaultEncoding && [collationName isEqualToString:tableCollation]) {
						NSAttributedString *itemString = [[NSAttributedString alloc] initWithString:[item title] attributes:menuAttrs];
						[item setAttributedTitle:[itemString autorelease]];
					}
				}

				// the popup cell is subclassed to take the representedObject instead of the item index
				return columnCollation;
			}
		}

		return nil;
	}
	else if ([[tableColumn identifier] isEqualToString:@"encoding"]) {
		// the encoding menu was already configured during setTableDetails:
		NSString *columnEncoding = [rowData objectForKey:@"encodingName"];

		if([columnEncoding length]) {
			NSInteger idx = [encodingPopupCell indexOfItemWithRepresentedObject:columnEncoding];
			if(idx > 0) return @(idx);
		}

		return @0;
	}
	else if ([[tableColumn identifier] isEqualToString:@"Extra"]) {
		id dataCell = [tableColumn dataCell];
		
		[dataCell removeAllItems];
		
		// Populate Extra suggestion popup button
		for (id item in extraFieldSuggestions) 
		{
			if (!(isCurrentExtraAutoIncrement && [item isEqualToString:@"auto_increment"])) {
				[dataCell addItemWithObjectValue:item];
			}
		}
	}

	return [rowData objectForKey:[tableColumn identifier]];
}

- (void)tableView:(NSTableView *)aTableView setObjectValue:(id)anObject forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	// Make sure that the operation is for the right table view
	if (aTableView != tableSourceView) return;

	NSMutableDictionary *currentRow = NSArrayObjectAtIndex(tableFields,rowIndex);
	
	if (!isEditingRow) {
		[oldRow setDictionary:currentRow];
		isEditingRow = YES;
		currentlyEditingRow = rowIndex;
	}

	// Reset collation if encoding was changed
	if ([[aTableColumn identifier] isEqualToString:@"encoding"]) {
		NSString *oldEncoding = [currentRow objectForKey:@"encodingName"];
		NSString *newEncoding = [[encodingPopupCell itemAtIndex:[anObject integerValue]] representedObject];
		if (![oldEncoding isEqualToString:newEncoding]) {
			[currentRow removeObjectForKey:@"collationName"];
			[tableSourceView reloadData];
		}
		if(!newEncoding)
			[currentRow removeObjectForKey:@"encodingName"];
		else
			[currentRow setObject:newEncoding forKey:@"encodingName"];
		return;
	}
	else if ([[aTableColumn identifier] isEqualToString:@"collation"]) {
		//the popup button is subclassed to return the representedObject instead of the item index
		NSString *newCollation = anObject;

		if(!newCollation)
			[currentRow removeObjectForKey:@"collationName"];
		else
			[currentRow setObject:newCollation forKey:@"collationName"];
		return;
	}
	// Reset collation if BINARY was changed, as enabling BINARY sets collation to *_bin
	else if ([[aTableColumn identifier] isEqualToString:@"binary"]) {
		if ([[currentRow objectForKey:@"binary"] integerValue] != [anObject integerValue]) {
			[currentRow removeObjectForKey:@"collationName"];

			[tableSourceView reloadData];
		}
	}
	// Set null field to "do not allow NULL" for auto_increment Extra and reset Extra suggestion list
	else if ([[aTableColumn identifier] isEqualToString:@"Extra"]) {
		if (![[currentRow objectForKey:@"Extra"] isEqualToString:anObject]) {

			isCurrentExtraAutoIncrement = [[[anObject stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString] isEqualToString:@"AUTO_INCREMENT"];
			
			if (isCurrentExtraAutoIncrement) {
				[currentRow setObject:@0 forKey:@"null"];

				// Asks the user to add an index to query if AUTO_INCREMENT is set and field isn't indexed
				if ((![currentRow objectForKey:@"Key"] || [[currentRow objectForKey:@"Key"] isEqualToString:@""])) {
#ifndef SP_CODA
					[chooseKeyButton selectItemWithTag:SPPrimaryKeyMenuTag];

					[NSApp beginSheet:keySheet
					   modalForWindow:[tableDocumentInstance parentWindow] modalDelegate:self
					   didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:)
						  contextInfo:@"autoincrementindex" ];
#endif
				}
			} 
			else {
				autoIncrementIndex = nil;
			}

			id dataCell = [aTableColumn dataCell];
			
			[dataCell removeAllItems];
			[dataCell addItemsWithObjectValues:extraFieldSuggestions];
			[dataCell noteNumberOfItemsChanged];
			[dataCell reloadData];
			
			[tableSourceView reloadData];

		}
	}
	// Reset default to "" if field doesn't allow NULL and current default is set to NULL
	else if ([[aTableColumn identifier] isEqualToString:@"null"]) {
		if ([[currentRow objectForKey:@"null"] integerValue] != [anObject integerValue]) {
			if ([anObject integerValue] == 0) {
				if ([[currentRow objectForKey:@"default"] isEqualToString:[prefs objectForKey:SPNullValue]]) {
					[currentRow setObject:@"" forKey:@"default"];
				}
			}
			
			[tableSourceView reloadData];
		}
	}
	// Store new value but not if user choose "---" for type and reset values if required
	else if ([[aTableColumn identifier] isEqualToString:@"type"]) {
		if (anObject && [(NSString*)anObject length] && ![(NSString*)anObject hasPrefix:@"--"]) {
			[currentRow setObject:[(NSString*)anObject uppercaseString] forKey:@"type"];
			
			// If type is BLOB or TEXT reset DEFAULT since these field types don't allow a default
			if ([[currentRow objectForKey:@"type"] hasSuffix:@"TEXT"] || 
				[[currentRow objectForKey:@"type"] hasSuffix:@"BLOB"] ||
				[[currentRow objectForKey:@"type"] isEqualToString:@"JSON"] ||
				[fieldValidation isFieldTypeGeometry:[currentRow objectForKey:@"type"]] ||
				([fieldValidation isFieldTypeDate:[currentRow objectForKey:@"type"]] && ![[currentRow objectForKey:@"type"] isEqualToString:@"YEAR"])) 
			{
				[currentRow setObject:@"" forKey:@"default"];
				[currentRow setObject:@"" forKey:@"length"];
			}
			
			[tableSourceView reloadData];
		}
		return;
	} 

	[currentRow setObject:(anObject) ? anObject : @"" forKey:[aTableColumn identifier]];
}

/**
 * Confirm whether to allow editing of a row. Returns YES by default, but NO for views.
 */
- (BOOL)tableView:(NSTableView *)aTableView shouldEditTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	if ([tableDocumentInstance isWorking]) return NO;
	
	// Return NO for views
	if ([tablesListInstance tableType] == SPTableTypeView) return NO;
	
	return YES;
}

/**
 * Begin a drag and drop operation from the table - copy a single dragged row to the drag pasteboard.
 */
- (BOOL)tableView:(NSTableView *)aTableView writeRowsWithIndexes:(NSIndexSet *)rows toPasteboard:(NSPasteboard*)pboard
{
	// Make sure that the drag operation is started from the right table view
	if (aTableView != tableSourceView) return NO;
	
	// Check whether a save of the current field row is required.
	if (![self saveRowOnDeselect]) return NO;
	
	if ([rows count] == 1) {
		[pboard declareTypes:@[SPDefaultPasteboardDragType] owner:nil];
		[pboard setString:[NSString stringWithFormat:@"%lu",[rows firstIndex]] forType:SPDefaultPasteboardDragType];
		
		return YES;
	} 
	
	return NO;
}

/**
 * Determine whether to allow a drag and drop operation on this table - for the purposes of drag reordering,
 * validate that the original source is of the correct type and within the same table, and that the drag
 * would result in a position change.
 */
- (NSDragOperation)tableView:(NSTableView*)tableView validateDrop:(id <NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)operation
{
    // Make sure that the drag operation is for the right table view
    if (tableView!=tableSourceView) return NSDragOperationNone;
	
	NSArray *pboardTypes = [[info draggingPasteboard] types];
	NSInteger originalRow;
	
	// Ensure the drop is of the correct type
	if (operation == NSTableViewDropAbove && row != -1 && [pboardTypes containsObject:SPDefaultPasteboardDragType]) {
		
		// Ensure the drag originated within this table
		if ([info draggingSource] == tableView) {
			originalRow = [[[info draggingPasteboard] stringForType:SPDefaultPasteboardDragType] integerValue];
			
			if (row != originalRow && row != (originalRow+1)) {
				return NSDragOperationMove;
			}
		}
	}
	
	return NSDragOperationNone;
}

/**
 * Having validated a drop, perform the field/column reordering to match.
 */
- (BOOL)tableView:(NSTableView*)tableView acceptDrop:(id <NSDraggingInfo>)info row:(NSInteger)destinationRowIndex dropOperation:(NSTableViewDropOperation)operation
{
    // Make sure that the drag operation is for the right table view
    if (tableView != tableSourceView) return NO;
		
	// Extract the original row position from the pasteboard and retrieve the details
	NSInteger originalRowIndex = [[[info draggingPasteboard] stringForType:SPDefaultPasteboardDragType] integerValue];
	NSDictionary *originalRow = [[NSDictionary alloc] initWithDictionary:[tableFields objectAtIndex:originalRowIndex]];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:@"SMySQLQueryWillBePerformed" object:tableDocumentInstance];

	// Begin construction of the reordering query
	NSMutableString *queryString = [NSMutableString stringWithFormat:@"ALTER TABLE %@ MODIFY COLUMN %@",
	                                                                 [selectedTable backtickQuotedString],
	                                                                 [self _buildPartialColumnDefinitionString:originalRow]];

	[queryString appendString:@" "];
	// Add the new location
	if (destinationRowIndex == 0) {
		[queryString appendString:@"FIRST"];
	} 
	else {
		[queryString appendFormat:@"AFTER %@", [[[tableFields objectAtIndex:destinationRowIndex - 1] objectForKey:@"name"] backtickQuotedString]];
	}
	
	// Run the query; report any errors, or reload the table on success
	[mySQLConnection queryString:queryString];
	
	if ([mySQLConnection queryErrored]) {
		SPOnewayAlertSheet(
			NSLocalizedString(@"Error moving field", @"error moving field message"),
			[tableDocumentInstance parentWindow],
			[NSString stringWithFormat:NSLocalizedString(@"An error occurred while trying to move the field.\n\nMySQL said: %@", @"error moving field informative message"), [mySQLConnection lastErrorMessage]]
		);
	} 
	else {
		[tableDataInstance resetAllData];
		[tableDocumentInstance setStatusRequiresReload:YES];
		
		[self loadTable:selectedTable];
		
		// Mark the content table cache for refresh
		[tableDocumentInstance setContentRequiresReload:YES];
		
		[tableSourceView selectRowIndexes:[NSIndexSet indexSetWithIndex:destinationRowIndex - ((originalRowIndex < destinationRowIndex) ? 1 : 0)] byExtendingSelection:NO];
	}
	
	[[NSNotificationCenter defaultCenter] postNotificationName:@"SMySQLQueryHasBeenPerformed" object:tableDocumentInstance];
	
	[originalRow release];
	
	return YES;
}

#pragma mark -
#pragma mark Table view delegate methods

- (BOOL)tableView:(NSTableView *)aTableView shouldSelectRow:(NSInteger)rowIndex
{
	// If we are editing a row, attempt to save that row - if saving failed, do not select the new row.
	if (isEditingRow && ![self addRowToDB]) return NO;
	
	return YES;
}

/**
 * Performs various interface validation
 */
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	// Check for which table view the selection changed
	if ([aNotification object] == tableSourceView) {
		
		// If we are editing a row, attempt to save that row - if saving failed, reselect the edit row.
		if (isEditingRow && [tableSourceView selectedRow] != currentlyEditingRow && ![self saveRowOnDeselect]) return;
		
		[duplicateFieldButton setEnabled:YES];
		
		// Check if there is currently a field selected and change button state accordingly
		if ([tableSourceView numberOfSelectedRows] > 0 && [tablesListInstance tableType] == SPTableTypeTable) {
			[removeFieldButton setEnabled:YES];
		} 
		else {
			[removeFieldButton setEnabled:NO];
			[duplicateFieldButton setEnabled:NO];
		}
		
		// If the table only has one field, disable the remove button. This removes the need to check that the user
		// is attempting to remove the last field in a table in removeField: above, but leave it in just in case.
		if ([tableSourceView numberOfRows] == 1) {
			[removeFieldButton setEnabled:NO];
		}
	}
}

/**
 * Traps enter and esc and make/cancel editing without entering next row
 */
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command
{
	NSInteger row, column;
	
	row = [tableSourceView editedRow];
	column = [tableSourceView editedColumn];
	
	// Trap the tab key, selecting the next item in the line
	if ([textView methodForSelector:command] == [textView methodForSelector:@selector(insertTab:)] && [tableSourceView numberOfColumns] - 1 == column)
	{
		//save current line
		[[control window] makeFirstResponder:control];
		
		if ([self addRowToDB] && [textView methodForSelector:command] == [textView methodForSelector:@selector(insertTab:)]) {
			if (row < ([tableSourceView numberOfRows] - 1)) {
				[tableSourceView selectRowIndexes:[NSIndexSet indexSetWithIndex:row + 1] byExtendingSelection:NO];
				[tableSourceView editColumn:0 row:row + 1 withEvent:nil select:YES];
			} 
			else {
				[tableSourceView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
				[tableSourceView editColumn:0 row:0 withEvent:nil select:YES];
			}
		}
		
		return YES;
	}
	// Trap shift-tab key
	else if ([textView methodForSelector:command] == [textView methodForSelector:@selector(insertBacktab:)] && column < 1)
	{
		if ([self addRowToDB] && [textView methodForSelector:command] == [textView methodForSelector:@selector(insertBacktab:)]) {
			[[control window] makeFirstResponder:control];
			
			if (row > 0) {
				[tableSourceView selectRowIndexes:[NSIndexSet indexSetWithIndex:row - 1] byExtendingSelection:NO];
				[tableSourceView editColumn:([tableSourceView numberOfColumns] - 1) row:row - 1 withEvent:nil select:YES];
			}
			else {
				[tableSourceView selectRowIndexes:[NSIndexSet indexSetWithIndex:([tableFields count] - 1)] byExtendingSelection:NO];
				[tableSourceView editColumn:([tableSourceView numberOfColumns] - 1) row:([tableSourceView numberOfRows] - 1) withEvent:nil select:YES];
			}
		}
		
		return YES;
	}
	// Trap the enter key, triggering a save
	else if ([textView methodForSelector:command] == [textView methodForSelector:@selector(insertNewline:)])
	{
		// Suppress enter for non-text fields to allow selecting of chosen items from comboboxes or popups
		if (![[[[[[tableSourceView tableColumns] objectAtIndex:column] dataCell] class] description] isEqualToString:@"NSTextFieldCell"]) {
			return YES;
		}
		
		[[control window] makeFirstResponder:control];
		
		[self addRowToDB];
		
		[tableSourceView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
		
		[[tableDocumentInstance parentWindow] makeFirstResponder:tableSourceView];
		
		return YES;
	}
	// Trap escape, aborting the edit and reverting the row
	else if ([[control window] methodForSelector:command] == [[control window] methodForSelector:@selector(cancelOperation:)])
	{
		[control abortEditing];
		
		[self cancelRowEditing];
		
		return YES;
	}

	return NO;
}

/**
 * Modify cell display by disabling table cells when a view is selected, meaning structure/index
 * is uneditable and do cell validation due to row's field type.
 */
- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)rowIndex
{
	// Make sure that the message is from the right table view
	if (tableView != tableSourceView) return;
	
	if ([tablesListInstance tableType] == SPTableTypeView) {
		[aCell setEnabled:NO];
	} 
	else {
		// Validate cell against current field type
		NSString *rowType;
		NSDictionary *row = NSArrayObjectAtIndex(tableFields, rowIndex);
		
		if ((rowType = [row objectForKey:@"type"])) {
			rowType = [[rowType stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
		}
		
		// Only string fields allow encoding settings, but JSON only uses utf8mb4
		if (([[tableColumn identifier] isEqualToString:@"encoding"])) {
			[aCell setEnabled:(![rowType isEqualToString:@"JSON"] && [fieldValidation isFieldTypeString:rowType] && [[tableDocumentInstance serverSupport] supportsPost41CharacterSetHandling])];
		}
		
		// Only string fields allow collation settings and string field is not set to BINARY since BINARY sets the collation to *_bin
		else if ([[tableColumn identifier] isEqualToString:@"collation"]) {
			// JSON always uses utf8mb4_bin which is already covered by this logic
 			[aCell setEnabled:([fieldValidation isFieldTypeString:rowType] && [[row objectForKey:@"binary"] integerValue] == 0 && [[tableDocumentInstance serverSupport] supportsPost41CharacterSetHandling])];
		}
		
		// Check if UNSIGNED and ZEROFILL is allowed
		else if ([[tableColumn identifier] isEqualToString:@"zerofill"] || [[tableColumn identifier] isEqualToString:@"unsigned"]) {
			[aCell setEnabled:([fieldValidation isFieldTypeNumeric:rowType] && ![rowType isEqualToString:@"BIT"])];
		}
		
		// Check if BINARY is allowed
		else if ([[tableColumn identifier] isEqualToString:@"binary"]) {
			// JSON always uses utf8mb4_bin
			[aCell setEnabled:(![rowType isEqualToString:@"JSON"] && [fieldValidation isFieldTypeAllowBinary:rowType])];
		}
		
		// TEXT, BLOB, GEOMETRY and JSON fields don't allow a DEFAULT
		else if ([[tableColumn identifier] isEqualToString:@"default"]) {
			[aCell setEnabled:([rowType hasSuffix:@"TEXT"] || [rowType hasSuffix:@"BLOB"] || [rowType isEqualToString:@"JSON"] || [fieldValidation isFieldTypeGeometry:rowType]) ? NO : YES];
		}
		
		// Check allow NULL
		else if ([[tableColumn identifier] isEqualToString:@"null"]) {			
			[aCell setEnabled:([[row objectForKey:@"Key"] isEqualToString:@"PRI"] || 
							   [[[row objectForKey:@"Extra"] uppercaseString] isEqualToString:@"AUTO_INCREMENT"] ||
							   [[[tableDataInstance statusValueForKey:@"Engine"] uppercaseString] isEqualToString:@"CSV"]) ? NO : YES];
		}
		
		// TEXT, BLOB, date, GEOMETRY and JSON fields don't allow a length
		else if ([[tableColumn identifier] isEqualToString:@"length"]) {
			[aCell setEnabled:([rowType hasSuffix:@"TEXT"] || 
							   [rowType hasSuffix:@"BLOB"] ||
			                   [rowType isEqualToString:@"JSON"] ||
							   ([fieldValidation isFieldTypeDate:rowType] && ![[tableDocumentInstance serverSupport] supportsFractionalSeconds] && ![rowType isEqualToString:@"YEAR"]) || 
							   [fieldValidation isFieldTypeGeometry:rowType]) ? NO : YES];
		}
		else {
			[aCell setEnabled:YES];
		}		
	}
}

#pragma mark -
#pragma mark Split view delegate methods
#ifndef SP_CODA /* Split view delegate methods */

- (BOOL)splitView:(NSSplitView *)sender canCollapseSubview:(NSView *)subview
{
	return YES;
}

- (CGFloat)splitView:(NSSplitView *)sender constrainMaxCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)offset
{
	return proposedMax - 130;
}

- (CGFloat)splitView:(NSSplitView *)sender constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)offset
{
	return proposedMin + 130;
}

- (NSRect)splitView:(NSSplitView *)splitView additionalEffectiveRectOfDividerAtIndex:(NSInteger)dividerIndex
{
	return [structureGrabber convertRect:[structureGrabber bounds] toView:splitView];
}

- (void)splitViewDidResizeSubviews:(NSNotification *)aNotification
{
	if ([aNotification object] == tablesIndexesSplitView) {
		
		NSView *indexesView = [[tablesIndexesSplitView subviews] objectAtIndex:1];
		
		if ([tablesIndexesSplitView isSubviewCollapsed:indexesView]) {
			[indexesShowButton setHidden:NO];
		} 
		else {
			[indexesShowButton setHidden:YES];
		}
	}
}
#endif

#pragma mark -
#pragma mark Combo box delegate methods

- (id)comboBoxCell:(NSComboBoxCell *)aComboBoxCell objectValueForItemAtIndex:(NSInteger)index
{
	return NSArrayObjectAtIndex(typeSuggestions, index);
}

- (NSInteger)numberOfItemsInComboBoxCell:(NSComboBoxCell *)aComboBoxCell
{
	return [typeSuggestions count];
}

/**
 * Allow completion of field data types of lowercased input.
 */
- (NSString *)comboBoxCell:(NSComboBoxCell *)aComboBoxCell completedString:(NSString *)uncompletedString
{
	if ([uncompletedString hasPrefix:@"-"]) return @"";
	
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF BEGINSWITH[c] %@", [uncompletedString uppercaseString]];
	NSArray *result = [typeSuggestions filteredArrayUsingPredicate:predicate];
	
	if ([result count]) return [result objectAtIndex:0];
	
	return @"";
}

- (void)comboBoxCell:(SPComboBoxCell *)cell willPopUpWindow:(NSWindow *)win
{
	// the selected item in the popup list is independent of the displayed text, we have to explicitly set it, too
	NSInteger pos = [typeSuggestions indexOfObject:[cell stringValue]];
	if(pos != NSNotFound) {
		[cell selectItemAtIndex:pos];
		[cell scrollItemAtIndexToTop:pos];
	}
	
	//set up the help window to the right position
	NSRect listFrame = [win frame];
	NSRect helpFrame = [structureHelpPanel frame];
	helpFrame.origin.y = listFrame.origin.y;
	helpFrame.size.height = listFrame.size.height;
	[structureHelpPanel setFrame:helpFrame display:YES];
	
	[self _displayFieldTypeHelpIfPossible:cell];
}

- (void)comboBoxCell:(SPComboBoxCell *)cell willDismissWindow:(NSWindow *)win
{
	//hide the window if it is still visible
	[structureHelpPanel orderOut:nil];
}

- (void)comboBoxCellSelectionDidChange:(SPComboBoxCell *)cell
{
	[self _displayFieldTypeHelpIfPossible:cell];
}

- (void)_displayFieldTypeHelpIfPossible:(SPComboBoxCell *)cell
{
	NSString *selected = [typeSuggestions objectOrNilAtIndex:[cell indexOfSelectedItem]];
	
	const SPFieldTypeHelp *help = [[self class] helpForFieldType:selected];
	
	if(help) {
		NSMutableAttributedString *as = [[NSMutableAttributedString alloc] init];
		
		//title
		{
			NSDictionary *titleAttr = @{NSFontAttributeName: [NSFont boldSystemFontOfSize:[NSFont systemFontSize]]};
			NSAttributedString *title = [[NSAttributedString alloc] initWithString:[help typeDefinition] attributes:titleAttr];
			[as appendAttributedString:[title autorelease]];
			[[as mutableString] appendString:@"\n"];
		}
		
		//range
		if([[help typeRange] length]) {
			NSDictionary *rangeAttr = @{NSFontAttributeName: [NSFont systemFontOfSize:[NSFont smallSystemFontSize]]};
			NSAttributedString *range = [[NSAttributedString alloc] initWithString:[help typeRange] attributes:rangeAttr];
			[as appendAttributedString:[range autorelease]];
			[[as mutableString] appendString:@"\n"];
		}
		
		[[as mutableString] appendString:@"\n"];
		
		//description
		{
			NSDictionary *descAttr = @{NSFontAttributeName: [NSFont systemFontOfSize:[NSFont systemFontSize]]};
			NSAttributedString *desc = [[NSAttributedString alloc] initWithString:[help typeDescription] attributes:descAttr];
			[as appendAttributedString:[desc autorelease]];
		}
		
		[as addAttribute:NSParagraphStyleAttributeName value:[NSParagraphStyle defaultParagraphStyle] range:NSMakeRange(0, [as length])];
		
		[[structureHelpText textStorage] setAttributedString:[as autorelease]];

		NSRect rect = [as boundingRectWithSize:NSMakeSize([structureHelpText frame].size.width-2, CGFLOAT_MAX) options:NSStringDrawingUsesFontLeading|NSStringDrawingUsesLineFragmentOrigin];
		
		NSRect winRect = [structureHelpPanel frame];
		
		CGFloat winAddonSize = (winRect.size.height - [[structureHelpPanel contentView] frame].size.height) + (6*2);
		
		NSRect popUpFrame = [[cell spPopUpWindow] frame];
		
		//determine the side on which to add our window based on the space left on screen
		NSPoint topRightCorner = NSMakePoint(popUpFrame.origin.x, NSMaxY(popUpFrame));
		NSRect screenRect = [NSScreen rectOfScreenAtPoint:topRightCorner];
		
		if(NSMaxX(popUpFrame)+10+winRect.size.width > NSMaxX(screenRect)-10) {
			// exceeds right border, display on the left
			winRect.origin.x = popUpFrame.origin.x - 10 - winRect.size.width;
		}
		else {
			// display on the right
			winRect.origin.x = NSMaxX(popUpFrame)+10;
		}
		
		winRect.size.height = rect.size.height + winAddonSize;
		winRect.origin.y = NSMaxY(popUpFrame) - winRect.size.height;
		[structureHelpPanel setFrame:winRect display:YES];
		
		[structureHelpPanel orderFront:nil];
	}
	else {
		[structureHelpPanel orderOut:nil];
	}
}

#pragma mark -
#pragma mark Menu delegate methods (encoding/collation dropdown menu)

- (void)menuNeedsUpdate:(SPIdMenu *)menu
{
	if(![menu isKindOfClass:[SPIdMenu class]]) return;
	//NOTE: NSTableView will usually copy the menu and call this method on the copy. Matching with == won't work!

	//walk through the menu and clear the attributedTitle if set. This will remove the gray color from the default items
	for(NSMenuItem *item in [menu itemArray]) {
		if([item attributedTitle]) {
			[item setAttributedTitle:nil];
		}
	}

	NSDictionary *rowData = NSArrayObjectAtIndex(tableFields, [tableSourceView selectedRow]);
	
	if([[menu menuId] isEqualToString:@"encodingPopupMenu"]) {
		NSString *tableEncoding = [tableDataInstance tableEncoding];
		//NSString *databaseEncoding = [databaseDataInstance getDatabaseDefaultCharacterSet];
		//NSString *serverEncoding = [databaseDataInstance getServerDefaultCharacterSet];

		struct _cmpMap defaultCmp[] = {
			{
				NSLocalizedString(@"Table",@"Table Structure : Encoding dropdown : 'item is table default' marker"),
				[NSString stringWithFormat:NSLocalizedString(@"This is the default encoding of table “%@”.", @"Table Structure : Encoding dropdown : table marker tooltip"),selectedTable],
				tableEncoding
			},
			/* //we could, but that might confuse users even more plus there is no inheritance between a columns charset and the db/server default
			{
				NSLocalizedString(@"Database",@"Table Structure : Encoding dropdown : 'item is database default' marker"),
				[NSString stringWithFormat:NSLocalizedString(@"This is the default encoding of database “%@”.", @"Table Structure : Encoding dropdown : database marker tooltip"),[tableDocumentInstance database]],
				databaseEncoding
			},
			{
				NSLocalizedString(@"Server",@"Table Structure : Encoding dropdown : 'item is server default' marker"),
				NSLocalizedString(@"This is the default encoding of this server.", @"Table Structure : Encoding dropdown : server marker tooltip"),
				serverEncoding
			} */
		};

		_BuildMenuWithPills(menu, defaultCmp, COUNT_OF(defaultCmp));
	}
	else if([[menu menuId] isEqualToString:@"collationPopupMenu"]) {
		NSString *encoding = [rowData objectForKey:@"encodingName"];
		NSString *encodingDefaultCollation = [databaseDataInstance getDefaultCollationForEncoding:encoding];
		NSString *tableCollation = [tableDataInstance statusValueForKey:@"Collation"];
		//NSString *databaseCollation = [databaseDataInstance getDatabaseDefaultCollation];
		//NSString *serverCollation = [databaseDataInstance getServerDefaultCollation];
		
		struct _cmpMap defaultCmp[] = {
			{
				NSLocalizedString(@"Default",@"Table Structure : Collation dropdown : 'item is the same as the default collation of the row's charset' marker"),
				[NSString stringWithFormat:NSLocalizedString(@"This is the default collation of encoding “%@”.", @"Table Structure : Collation dropdown : default marker tooltip"),encoding],
				encodingDefaultCollation
			},
			{
				NSLocalizedString(@"Table",@"Table Structure : Collation dropdown : 'item is the same as the collation of table' marker"),
				[NSString stringWithFormat:NSLocalizedString(@"This is the default collation of table “%@”.", @"Table Structure : Collation dropdown : table marker tooltip"),selectedTable],
				tableCollation
			},
			/* // see the comment for charset above
			{
				NSLocalizedString(@"Database",@"Table Structure : Collation dropdown : 'item is the same as the collation of database' marker"),
				[NSString stringWithFormat:NSLocalizedString(@"This is the default collation of database “%@”.", @"Table Structure : Collation dropdown : database marker tooltip"),[tableDocumentInstance database]],
				databaseCollation
			},
			{
				NSLocalizedString(@"Server",@"Table Structure : Collation dropdown : 'item is the same as the collation of server' marker"),
				NSLocalizedString(@"This is the default collation of this server.", @"Table Structure : Collation dropdown : server marker tooltip"),
				serverCollation
			} */
		};
		
		_BuildMenuWithPills(menu, defaultCmp, COUNT_OF(defaultCmp));
	}
}

@end

void _BuildMenuWithPills(NSMenu *menu,struct _cmpMap *map,size_t mapEntries)
{
	NSDictionary *baseAttrs = @{NSFontAttributeName:[menu font],NSParagraphStyleAttributeName: [NSParagraphStyle defaultParagraphStyle]};
	
	for(NSMenuItem *item in [menu itemArray]) {
		NSMutableAttributedString *itemStr = [[NSMutableAttributedString alloc] initWithString:[item title] attributes:baseAttrs];
		NSString *value = [item representedObject];
		
		NSMutableArray *tooltipParts = [NSMutableArray array];
		for (unsigned int i = 0; i < mapEntries; ++i) {
			struct _cmpMap *cmp = &map[i];
			if([cmp->cmpWith isEqualToString:value]) {
				SPPillAttachmentCell *cell = [[SPPillAttachmentCell alloc] init];
				[cell setStringValue:cmp->title];
				NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
				[attachment setAttachmentCell:[cell autorelease]];
				NSAttributedString *attachmentString = [NSAttributedString attributedStringWithAttachment:[attachment autorelease]];
				
				[[itemStr mutableString] appendString:@" "];
				[itemStr appendAttributedString:attachmentString];
				
				if(cmp->tooltipPart) [tooltipParts addObject:cmp->tooltipPart];
			}
		}
		if([tooltipParts count]) [item setToolTip:[tooltipParts componentsJoinedByString:@" "]];
		
		[item setAttributedTitle:[itemStr autorelease]];
	}
}
