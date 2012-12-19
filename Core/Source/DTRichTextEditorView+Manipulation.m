//
//  DTRichTextEditorView+Manipulation.m
//  DTRichTextEditor
//
//  Created by Oliver Drobnik on 17.12.12.
//  Copyright (c) 2012 Cocoanetics. All rights reserved.
//

#import "DTRichTextEditor.h"

@interface DTRichTextEditorView (private)

- (void)updateCursorAnimated:(BOOL)animated;
- (void)hideContextMenu;

@property (nonatomic, retain) NSDictionary *overrideInsertionAttributes;

@end


@implementation DTRichTextEditorView (Manipulation)

#pragma mark - Getting/Setting content

- (NSAttributedString *)attributedSubstringForRange:(UITextRange *)range
{
	DTTextRange *textRange = (DTTextRange *)range;
	
	return [self.contentView.layoutFrame.attributedStringFragment attributedSubstringFromRange:[textRange NSRangeValue]];
}

- (void)setHTMLString:(NSString *)string
{
	NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
	
	NSAttributedString *attributedString = [[NSAttributedString alloc] initWithHTMLData:data options:[self textDefaults] documentAttributes:NULL];
	
	[self setAttributedText:attributedString];
}

- (NSString *)plainTextForRange:(UITextRange *)range
{
	if (!range)
	{
		return nil;
	}
	
	NSRange textRange = [(DTTextRange *)range NSRangeValue];
	
	NSString *tmpString = [[self.contentView.layoutFrame.attributedStringFragment string] substringWithRange:textRange];
	
	tmpString = [tmpString stringByReplacingOccurrencesOfString:UNICODE_OBJECT_PLACEHOLDER withString:@""];
	
	return tmpString;
};

#pragma mark - Working with Ranges
- (UITextRange *)textRangeOfWordAtPosition:(UITextPosition *)position
{
	DTTextRange *forRange = (id)[[self tokenizer] rangeEnclosingPosition:position withGranularity:UITextGranularityWord inDirection:UITextStorageDirectionForward];
	DTTextRange *backRange = (id)[[self tokenizer] rangeEnclosingPosition:position withGranularity:UITextGranularityWord inDirection:UITextStorageDirectionBackward];
	
	if (forRange && backRange)
	{
		DTTextRange *newRange = [DTTextRange textRangeFromStart:[backRange start] toEnd:[backRange end]];
		return newRange;
	}
	else if (forRange)
	{
		return forRange;
	}
	else if (backRange)
	{
		return backRange;
	}
	
	// treat image as word, left side of image selects it
	UITextPosition *plusOnePosition = [self positionFromPosition:position offset:1];
	UITextRange *imageRange = [self textRangeFromPosition:position toPosition:plusOnePosition];
	
	NSAttributedString *characterString = [self attributedSubstringForRange:imageRange];
	
	if ([[characterString attributesAtIndex:0 effectiveRange:NULL] objectForKey:NSAttachmentAttributeName])
	{
		return imageRange;
	}
	
	// we did not get a forward or backward range, like Word!|
	DTTextPosition *previousPosition = (id)([self.tokenizer positionFromPosition:position
																					 toBoundary:UITextGranularityCharacter
																					inDirection:UITextStorageDirectionBackward]);
	
	// treat image as word, right side of image selects it
	characterString = [self.contentView.layoutFrame.attributedStringFragment attributedSubstringFromRange:NSMakeRange(previousPosition.location, 1)];
	
	if ([[characterString attributesAtIndex:0 effectiveRange:NULL] objectForKey:NSAttachmentAttributeName])
	{
		return [DTTextRange textRangeFromStart:previousPosition toEnd:[previousPosition textPositionWithOffset:1]];
	}
	
	forRange = (id)[[self tokenizer] rangeEnclosingPosition:previousPosition withGranularity:UITextGranularityWord inDirection:UITextStorageDirectionForward];
	backRange = (id)[[self tokenizer] rangeEnclosingPosition:previousPosition withGranularity:UITextGranularityWord inDirection:UITextStorageDirectionBackward];
	
	UITextRange *retRange = nil;
	
	if (forRange && backRange)
	{
		retRange = [DTTextRange textRangeFromStart:[backRange start] toEnd:[backRange end]];
	}
	else if (forRange)
	{
		retRange = forRange;
	}
	else if (backRange)
	{
		retRange = backRange;
	}
	
	// need to extend to include the previous position
	if (retRange)
	{
		// extend this range to go up to current position
		return [DTTextRange textRangeFromStart:[retRange start] toEnd:position];
	}
	
	return nil;
}

- (UITextRange *)textRangeOfURLAtPosition:(UITextPosition *)position URL:(NSURL **)URL
{
	NSUInteger index = [(DTTextPosition *)position location];
	
	NSRange effectiveRange;
	
	NSURL *effectiveURL = [self.contentView.layoutFrame.attributedStringFragment attribute:DTLinkAttribute atIndex:index effectiveRange:&effectiveRange];
	
	if (!effectiveURL)
	{
		return nil;
	}
	
	DTTextRange *range = [DTTextRange rangeWithNSRange:effectiveRange];
	
	if (URL)
	{
		*URL = effectiveURL;
	}
	
	return range;
}

- (UITextRange *)textRangeOfParagraphsContainingRange:(UITextRange *)range
{
	NSRange myRange = [(DTTextRange *)range NSRangeValue];
	
	// get range containing all selected paragraphs
	NSAttributedString *attributedString = [contentView.layoutFrame attributedStringFragment];
	
	NSString *string = [attributedString string];
	
	NSUInteger begIndex;
	NSUInteger endIndex;
	
	[string rangeOfParagraphsContainingRange:myRange parBegIndex:&begIndex parEndIndex:&endIndex];
	myRange = NSMakeRange(begIndex, endIndex - begIndex); // now extended to full paragraphs
	
	DTTextRange *retRange = [DTTextRange rangeWithNSRange:myRange];

	return retRange;
}

- (NSDictionary *)typingAttributesForRange:(DTTextRange *)range
{
	NSDictionary *attributes = [self.contentView.layoutFrame.attributedStringFragment typingAttributesForRange:[range NSRangeValue]];
	
	CTFontRef font = (__bridge CTFontRef)[attributes objectForKey:(id)kCTFontAttributeName];
	CTParagraphStyleRef paragraphStyle = (__bridge CTParagraphStyleRef)[attributes objectForKey:(id)kCTParagraphStyleAttributeName];
	
	if (font&&paragraphStyle)
	{
		return attributes;
	}
	
	// otherwise we need to add missing things
	
	NSDictionary *defaults = [self textDefaults];
	NSString *fontFamily = [defaults objectForKey:DTDefaultFontFamily];
	
	CGFloat multiplier = [[defaults objectForKey:NSTextSizeMultiplierDocumentOption] floatValue];
	
	if (!multiplier)
	{
		multiplier = 1.0;
	}
	
	NSMutableDictionary *tmpAttributes = [attributes mutableCopy];
	
	// if there's no font, then substitute it from our defaults
	if (!font)
	{
		DTCoreTextFontDescriptor *desc = [[DTCoreTextFontDescriptor alloc] init];
		desc.fontFamily = fontFamily;
		desc.pointSize = 12.0 * multiplier;
		
		CTFontRef defaultFont = [desc newMatchingFont];
		
		[tmpAttributes setObject:(__bridge id)defaultFont forKey:(id)kCTFontAttributeName];
		
		CFRelease(defaultFont);
	}
	
	if (!paragraphStyle)
	{
		DTCoreTextParagraphStyle *defaultStyle = [DTCoreTextParagraphStyle defaultParagraphStyle];
		defaultStyle.paragraphSpacing = 12.0 * multiplier;
		
		paragraphStyle = [defaultStyle createCTParagraphStyle];
		
		[tmpAttributes setObject:(__bridge id)paragraphStyle forKey:(id)kCTParagraphStyleAttributeName];
		
		CFRelease(paragraphStyle);
	}
	
	return tmpAttributes;
}

#pragma mark - Pasteboard

- (BOOL)pasteboardHasSuitableContentForPaste
{
	UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
	
	if ([pasteboard containsPasteboardTypes:UIPasteboardTypeListString])
	{
		return YES;
	}
	
	if ([pasteboard containsPasteboardTypes:UIPasteboardTypeListImage])
	{
		return YES;
	}
	
	if ([pasteboard containsPasteboardTypes:UIPasteboardTypeListURL])
	{
		return YES;
	}
	
	if ([pasteboard webArchive])
	{
		return YES;
	}
	
	return NO;
}

#pragma mark - Utilities

// updates a text framement by replacing it with a new string
- (void)_updateSubstringInRange:(NSRange)range withAttributedString:(NSAttributedString *)attributedString actionName:(NSString *)actionName
{
	NSAssert([attributedString length] == range.length, @"lenght of updated string and update attributed string must match");
	
	NSUndoManager *undoManager = self.undoManager;
	
	NSAttributedString *replacedString = [self.contentView.attributedString attributedSubstringFromRange:range];
	
	[[undoManager prepareWithInvocationTarget:self] _updateSubstringInRange:range withAttributedString:replacedString actionName:actionName];
	
	if (actionName)
	{
		[undoManager setActionName:actionName];
	}
	
	// replace
	[(DTRichTextEditorContentView *)self.contentView replaceTextInRange:range withText:attributedString];
}

#pragma mark - Toggling Styles for Ranges

- (void)toggleBoldInRange:(DTTextRange *)range
{
	if ([range isEmpty])
	{
		// if we only have a cursor then we save the attributes for the next insertion
		NSMutableDictionary *tmpDict = [self.overrideInsertionAttributes mutableCopy];
		
		if (!tmpDict)
		{
			tmpDict = [[self typingAttributesForRange:range] mutableCopy];
		}
		[tmpDict toggleBold];
		self.overrideInsertionAttributes = tmpDict;
	}
	else
	{
		NSRange styleRange = [(DTTextRange *)range NSRangeValue];
		
		// get fragment that is to be made bold
		NSMutableAttributedString *fragment = [[[contentView.layoutFrame attributedStringFragment] attributedSubstringFromRange:styleRange] mutableCopy];
		
		// make entire frament bold
		[fragment toggleBoldInRange:NSMakeRange(0, [fragment length])];
	
		// replace
		[self _updateSubstringInRange:styleRange withAttributedString:fragment actionName:NSLocalizedString(@"Bold", @"Action that makes text bold")];
		
		// cursor positions might have changed
		[self updateCursorAnimated:NO];
	}
	
	[self hideContextMenu];
}

- (void)toggleItalicInRange:(DTTextRange *)range
{
	if ([range isEmpty])
	{
		// if we only have a cursor then we save the attributes for the next insertion
		NSMutableDictionary *tmpDict = [self.overrideInsertionAttributes mutableCopy];
		
		if (!tmpDict)
		{
			tmpDict = [[self typingAttributesForRange:range] mutableCopy];
		}
		[tmpDict toggleItalic];
		self.overrideInsertionAttributes = tmpDict;
	}
	else
	{
		NSRange styleRange = [(DTTextRange *)range NSRangeValue];
		
		// get fragment that is to be made italic
		NSMutableAttributedString *fragment = [[[contentView.layoutFrame attributedStringFragment] attributedSubstringFromRange:styleRange] mutableCopy];
		
		// make entire frament italic
		[fragment toggleItalicInRange:NSMakeRange(0, [fragment length])];

		// replace
		[self _updateSubstringInRange:styleRange withAttributedString:fragment actionName:NSLocalizedString(@"Italic", @"Action that makes text italic")];
		
		// attachment positions might have changed
		[self.contentView layoutSubviewsInRect:self.bounds];
		
		// cursor positions might have changed
		[self updateCursorAnimated:NO];
	}
	
	[self hideContextMenu];
}

- (void)toggleUnderlineInRange:(DTTextRange *)range
{
	if ([range isEmpty])
	{
		// if we only have a cursor then we save the attributes for the next insertion
		NSMutableDictionary *tmpDict = [self.overrideInsertionAttributes mutableCopy];
		
		if (!tmpDict)
		{
			tmpDict = [[self typingAttributesForRange:range] mutableCopy];
		}
		[tmpDict toggleUnderline];
		self.overrideInsertionAttributes = tmpDict;
	}
	else
	{
		NSRange styleRange = [(DTTextRange *)range NSRangeValue];
		
		// get fragment that is to be made underlined
		NSMutableAttributedString *fragment = [[[contentView.layoutFrame attributedStringFragment] attributedSubstringFromRange:styleRange] mutableCopy];
		
		// make entire frament underlined
		[fragment toggleUnderlineInRange:NSMakeRange(0, [fragment length])];
		
		// replace
		[self _updateSubstringInRange:styleRange withAttributedString:fragment actionName:NSLocalizedString(@"Underline", @"Action that makes text underlined")];
		
		// attachment positions might have changed
		[self.contentView layoutSubviewsInRect:self.bounds];
		
		// cursor positions might have changed
		[self updateCursorAnimated:NO];
	}
	
	[self hideContextMenu];
}

- (void)toggleHighlightInRange:(DTTextRange *)range color:(UIColor *)color
{
	if ([range isEmpty])
	{
		// if we only have a cursor then we save the attributes for the next insertion
		NSMutableDictionary *tmpDict = [self.overrideInsertionAttributes mutableCopy];
		
		if (!tmpDict)
		{
			tmpDict = [[self typingAttributesForRange:range] mutableCopy];
		}
		[tmpDict toggleHighlightWithColor:color];
		self.overrideInsertionAttributes = tmpDict;
	}
	else
	{
		NSRange styleRange = [(DTTextRange *)range NSRangeValue];
		
		// get fragment that is to be made bold
		NSMutableAttributedString *fragment = [[[contentView.layoutFrame attributedStringFragment] attributedSubstringFromRange:styleRange] mutableCopy];
		
		// make entire frament highlighted
		[fragment toggleHighlightInRange:NSMakeRange(0, [fragment length]) color:color];
		
		// replace
		[self _updateSubstringInRange:styleRange withAttributedString:fragment actionName:NSLocalizedString(@"Highlight", @"Action that adds a colored background behind text to highlight it")];
		
		// attachment positions might have changed
		[self.contentView layoutSubviewsInRect:self.bounds];
		
		// cursor positions might have changed
		[self updateCursorAnimated:NO];
	}
	
	[self hideContextMenu];
}

- (void)toggleHyperlinkInRange:(UITextRange *)range URL:(NSURL *)URL
{
	// if there is an URL at the cursor position we assume it
	NSURL *effectiveURL = nil;
	UITextRange *effectiveRange = [self textRangeOfURLAtPosition:range.start URL:&effectiveURL];
	
	if ([effectiveURL isEqual:URL])
	{
		// toggle URL off
		URL = nil;
	}
	
	if ([range isEmpty])
	{
		if (effectiveRange)
		{
			// work with the effective range instead
			range = effectiveRange;
		}
		else
		{
			// cannot toggle with empty range
			return;
		}
	}
	
	NSRange styleRange = [(DTTextRange *)range NSRangeValue];
	
	// get fragment that is to be toggled
	NSMutableAttributedString *fragment = [[[contentView.layoutFrame attributedStringFragment] attributedSubstringFromRange:styleRange] mutableCopy];
	
	// toggle entire frament
	NSRange entireFragmentRange = NSMakeRange(0, [fragment length]);
	[fragment toggleHyperlinkInRange:entireFragmentRange URL:URL];
	
	NSDictionary *textDefaults = self.textDefaults;
	
	// remove extra stylings
	[fragment removeAttribute:(id)kCTUnderlineStyleAttributeName range:entireFragmentRange];
	
	// assume normal text color is black
	[fragment addAttribute:(id)kCTForegroundColorAttributeName value:(id)[UIColor blackColor].CGColor range:entireFragmentRange];
	
	if (URL)
	{
		if ([[textDefaults objectForKey:DTDefaultLinkDecoration] boolValue])
		{
			[fragment addAttribute:(id)kCTUnderlineStyleAttributeName  value:[NSNumber numberWithInteger:1] range:entireFragmentRange];
		}
		
		UIColor *linkColor = [textDefaults objectForKey:DTDefaultLinkColor];
		
		if (linkColor)
		{
			[fragment addAttribute:(id)kCTForegroundColorAttributeName value:(id)linkColor.CGColor range:entireFragmentRange];
		}
		
	}
	
	// need to style the text accordingly
	
	// replace
	[self _updateSubstringInRange:styleRange withAttributedString:fragment actionName:NSLocalizedString(@"Hyperlink", @"Action that toggles text to be a hyperlink")];
	
	// attachment positions might have changed
	[self.contentView layoutSubviewsInRect:self.bounds];
	
	// cursor positions might have changed
	[self updateCursorAnimated:NO];
	
	[self hideContextMenu];
}

#pragma mark - Changing Paragraph Styles

- (BOOL)applyTextAlignment:(CTTextAlignment)alignment toParagraphsContainingRange:(UITextRange *)range
{
	DTTextRange *paragraphRange = (DTTextRange *)[self textRangeOfParagraphsContainingRange:range];
	NSMutableAttributedString *fragment = [[self attributedSubstringForRange:paragraphRange] mutableCopy];
	
	// adjust
	NSRange entireRange = NSMakeRange(0, [fragment length]);
	BOOL didUpdate = [fragment enumerateAndUpdateParagraphStylesInRange:entireRange block:^BOOL(DTCoreTextParagraphStyle *paragraphStyle, BOOL *stop) {
		if (paragraphStyle.alignment != alignment)
		{
			paragraphStyle.alignment = alignment;
			return YES;
		}
		
		return NO;
	}];

	if (didUpdate)
	{
		// replace
		[self _updateSubstringInRange:[paragraphRange NSRangeValue] withAttributedString:fragment actionName:NSLocalizedString(@"Alignment", @"Action that adjusts paragraph alignment")];
		
		// attachment positions might have changed
		[self.contentView layoutSubviewsInRect:self.bounds];
		
		// cursor positions might have changed
		[self updateCursorAnimated:NO];
	}
	
	[self hideContextMenu];

	return didUpdate;
}

- (void)changeParagraphLeftMarginBy:(CGFloat)delta toParagraphsContainingRange:(UITextRange *)range
{
	DTTextRange *paragraphRange = (DTTextRange *)[self textRangeOfParagraphsContainingRange:range];
	NSMutableAttributedString *fragment = [[self attributedSubstringForRange:paragraphRange] mutableCopy];
	
	// adjust
	NSRange entireRange = NSMakeRange(0, [fragment length]);
	BOOL didUpdate = [fragment enumerateAndUpdateParagraphStylesInRange:entireRange block:^BOOL(DTCoreTextParagraphStyle *paragraphStyle, BOOL *stop) {
		
		CGFloat newFirstLineIndent = paragraphStyle.firstLineHeadIndent + delta;
		
		if (newFirstLineIndent < 0)
		{
			newFirstLineIndent = 0;
		}
		
		CGFloat newOtherLineIndent = paragraphStyle.headIndent + delta;

		if (newOtherLineIndent < 0)
		{
			newOtherLineIndent = 0;
		}
		
		paragraphStyle.firstLineHeadIndent = newFirstLineIndent;
		paragraphStyle.headIndent = newOtherLineIndent;

		return YES;
	}];
	
	if (didUpdate)
	{
		// replace
		[self _updateSubstringInRange:[paragraphRange NSRangeValue] withAttributedString:fragment actionName:NSLocalizedString(@"Indent", @"Action that changes the indentation of a paragraph")];
		
		// attachment positions might have changed
		[self.contentView layoutSubviewsInRect:self.bounds];
		
		// cursor positions might have changed
		[self updateCursorAnimated:NO];
	}
	
	[self hideContextMenu];
}

- (void)toggleListStyle:(DTCSSListStyle *)listStyle inRange:(UITextRange *)range
{
	NSRange styleRange = [(DTTextRange *)range NSRangeValue];
	
	NSRange rangeToSelectAfterwards = styleRange;
	
	// get range containing all selected paragraphs
	NSAttributedString *attributedString = [contentView.layoutFrame attributedStringFragment];
	
	NSString *string = [attributedString string];
	
	NSUInteger begIndex;
	NSUInteger endIndex;
	
	[string rangeOfParagraphsContainingRange:styleRange parBegIndex:&begIndex parEndIndex:&endIndex];
	styleRange = NSMakeRange(begIndex, endIndex - begIndex); // now extended to full paragraphs
	
	NSMutableAttributedString *entireAttributedString = (NSMutableAttributedString *)[contentView.layoutFrame attributedStringFragment];
	
	// check if we are extending a list
	DTCSSListStyle *extendingList = nil;
	NSInteger nextItemNumber;
	
	if (styleRange.location>0)
	{
		NSArray *lists = [entireAttributedString attribute:DTTextListsAttribute atIndex:styleRange.location-1 effectiveRange:NULL];
		
		extendingList = [lists lastObject];
		
		if (extendingList.type == listStyle.type)
		{
			listStyle = extendingList;
		}
	}
	
	if (extendingList)
	{
		nextItemNumber = [entireAttributedString itemNumberInTextList:extendingList atIndex:styleRange.location-1]+1;
	}
	else
	{
		nextItemNumber = [listStyle startingItemNumber];
	}
	
	// remember current markers
	[entireAttributedString addMarkersForSelectionRange:rangeToSelectAfterwards];
	
	// toggle the list style
	[entireAttributedString toggleListStyle:listStyle inRange:styleRange numberFrom:nextItemNumber];
	
	// selected range has shifted
	rangeToSelectAfterwards = [entireAttributedString markedRangeRemove:YES];
	
	// relayout range of entire list
	//NSRange listRange = [entireAttributedString rangeOfTextList:listStyle atIndex:styleRange.location];
	//[(DTRichTextEditorContentView *)self.contentView relayoutTextInRange:rangeToSelectAfterwards];
	[self.contentView relayoutText];
	
	// get fragment that is to be changed
	//	NSMutableAttributedString *fragment = [[entireAttributedString attributedSubstringFromRange:styleRange] mutableCopy];
	
	//	NSRange fragmentRange = NSMakeRange(0, [fragment length]);
	
	//	[fragment toggleListStyle:listStyle inRange:fragmentRange numberFrom:nextItemNumber];
	
	// replace
	//	[(DTRichTextEditorContentView *)self.contentView replaceTextInRange:styleRange withText:fragment];
	
	//	styleRange.length = [fragment length];
	self.selectedTextRange = [DTTextRange rangeWithNSRange:rangeToSelectAfterwards];
	
	// attachment positions might have changed
	[self.contentView layoutSubviewsInRect:self.bounds];
	
	// cursor positions might have changed
	[self updateCursorAnimated:NO];
	
	[self hideContextMenu];
}

#pragma mark - Working with Attachments

- (void)replaceRange:(DTTextRange *)range withAttachment:(DTTextAttachment *)attachment inParagraph:(BOOL)inParagraph
{
	NSRange textRange = [(DTTextRange *)range NSRangeValue];
	
	NSMutableDictionary *attributes = [[self typingAttributesForRange:range] mutableCopy];
	
	// just in case if there is an attachment at the insertion point
	[attributes removeAttachment];
	
	BOOL needsParagraphBefore = NO;
	BOOL needsParagraphAfter = NO;
	
	NSString *plainText = [self.contentView.layoutFrame.attributedStringFragment string];
	
	if (inParagraph)
	{
		// determine if we need a paragraph break before or after the item
		if (textRange.location>0)
		{
			NSInteger index = textRange.location-1;
			
			unichar character = [plainText characterAtIndex:index];
			
			if (character != '\n')
			{
				needsParagraphBefore = YES;
			}
		}
		
		NSUInteger indexAfterRange = NSMaxRange(textRange);
		if (indexAfterRange<[plainText length])
		{
			unichar character = [plainText characterAtIndex:indexAfterRange];
			
			if (character != '\n')
			{
				needsParagraphAfter = YES;
			}
		}
	}
	NSMutableAttributedString *tmpAttributedString = [[NSMutableAttributedString alloc] initWithString:@""];
	
	if (needsParagraphBefore)
	{
		NSAttributedString *formattedNL = [[NSAttributedString alloc] initWithString:@"\n" attributes:attributes];
		[tmpAttributedString appendAttributedString:formattedNL];
	}
	
	NSMutableDictionary *objectAttributes = [attributes mutableCopy];
	
	// need run delegate for sizing
	CTRunDelegateRef embeddedObjectRunDelegate = createEmbeddedObjectRunDelegate((id)attachment);
	[objectAttributes setObject:(__bridge id)embeddedObjectRunDelegate forKey:(id)kCTRunDelegateAttributeName];
	CFRelease(embeddedObjectRunDelegate);
	
	// add attachment
	[objectAttributes setObject:attachment forKey:NSAttachmentAttributeName];
	
	// get the font
	CTFontRef font = (__bridge CTFontRef)[objectAttributes objectForKey:(__bridge NSString *) kCTFontAttributeName];
	if (font)
	{
		[attachment adjustVerticalAlignmentForFont:font];
	}
	
	NSAttributedString *tmpStr = [[NSAttributedString alloc] initWithString:UNICODE_OBJECT_PLACEHOLDER attributes:objectAttributes];
	[tmpAttributedString appendAttributedString:tmpStr];
	
	if (needsParagraphAfter)
	{
		NSAttributedString *formattedNL = [[NSAttributedString alloc] initWithString:@"\n" attributes:attributes];
		[tmpAttributedString appendAttributedString:formattedNL];
	}
	
	//NSUInteger replacementLength = [tmpAttributedString length];
	DTTextRange *replacementRange = [DTTextRange rangeWithNSRange:textRange];
	[self replaceRange:replacementRange withText:tmpAttributedString];
	
	/*
	 
	 // need to notify input delegate to remove autocorrection candidate view if present
	 [self.inputDelegate textWillChange:self];
	 
	 [(DTRichTextEditorContentView *)self.contentView replaceTextInRange:textRange withText:tmpAttributedString];
	 
	 [self.inputDelegate textDidChange:self];
	 
	 if (self->_keyboardIsShowing)
	 {
	 self.selectedTextRange = [DTTextRange emptyRangeAtPosition:[range start] offset:replacementLength];
	 }
	 else
	 {
	 self.selectedTextRange = nil;
	 }
	 
	 [self updateCursorAnimated:NO];
	 
	 // this causes the image to appear, layout gets the custom view for the image
	 [self setNeedsLayout];
	 
	 // send change notification
	 [[NSNotificationCenter defaultCenter] postNotificationName:DTRichTextEditorTextDidBeginEditingNotification object:self userInfo:nil];
	 */
}



- (NSArray *)textAttachmentsWithPredicate:(NSPredicate *)predicate
{
	// update all attachments that matchin this URL (possibly multiple images with same size)
	return [self.contentView.layoutFrame textAttachmentsWithPredicate:predicate];
}

@end