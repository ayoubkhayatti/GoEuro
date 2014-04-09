- (void)handleLongPressGesture:(UILongPressGestureRecognizer *)gestureRecognizer {
    switch(gestureRecognizer.state) {
        case UIGestureRecognizerStateBegan: {
            
            NSIndexPath *currentIndexPath = [self.collectionView indexPathForItemAtPoint:[gestureRecognizer locationInView:self.collectionView]];
            
            if ([self.dataSource respondsToSelector:@selector(collectionView:canMoveItemAtIndexPath:)] &&
               ![self.dataSource collectionView:self.collectionView canMoveItemAtIndexPath:currentIndexPath]) {
                return;
            }
            
            self.selectedItemIndexPath = currentIndexPath;
            
            if ([self.delegate respondsToSelector:@selector(collectionView:layout:willBeginDraggingItemAtIndexPath:)]) {
                [self.delegate collectionView:self.collectionView layout:self willBeginDraggingItemAtIndexPath:self.selectedItemIndexPath];
            }
            
            UICollectionViewCell *collectionViewCell = [self.collectionView cellForItemAtIndexPath:self.selectedItemIndexPath];
            
            self.currentView = [[UIView alloc] initWithFrame:collectionViewCell.frame];
            
            collectionViewCell.highlighted = YES;
            UIImageView *highlightedImageView = [[UIImageView alloc] initWithImage:[collectionViewCell LX_rasterizedImage]];
            highlightedImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            highlightedImageView.alpha = 1.0f;
            highlightedImageView.image = [self getLighterImage:highlightedImageView.image];
            
            collectionViewCell.highlighted = NO;
            UIImageView *imageView = [[UIImageView alloc] initWithImage:[collectionViewCell LX_rasterizedImage]];
            imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            imageView.alpha = 0.0f;
            imageView.image = [self getLighterImage:imageView.image];

            [self.currentView addSubview:imageView];
            [self.currentView addSubview:highlightedImageView];
            [self.collectionView addSubview:self.currentView];
            
            self.currentViewCenter = self.currentView.center;
            
            __weak typeof(self) weakSelf = self;
            [UIView
             animateWithDuration:0.3
             delay:0.0
             options:UIViewAnimationOptionBeginFromCurrentState
             animations:^{
                 __strong typeof(self) strongSelf = weakSelf;
                 if (strongSelf) {
                     strongSelf.currentView.transform = CGAffineTransformMakeScale(1.1f, 1.1f);
                     highlightedImageView.alpha = 1.0f;
                     imageView.alpha = 1.0f;
                 }
             }
             completion:^(BOOL finished) {
                 __strong typeof(self) strongSelf = weakSelf;
                 if (strongSelf) {
                     [highlightedImageView removeFromSuperview];
                     
                     if ([strongSelf.delegate respondsToSelector:@selector(collectionView:layout:didBeginDraggingItemAtIndexPath:)]) {
                         [strongSelf.delegate collectionView:strongSelf.collectionView layout:strongSelf didBeginDraggingItemAtIndexPath:strongSelf.selectedItemIndexPath];
                     }
                 }
             }];
            
            [self invalidateLayout];
        } break;
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateEnded: {
            
            NSIndexPath *currentIndexPath = self.selectedItemIndexPath;
            
            if (currentIndexPath) {
                if ([self.delegate respondsToSelector:@selector(collectionView:layout:willEndDraggingItemAtIndexPath:)]) {
                    [self.delegate collectionView:self.collectionView layout:self willEndDraggingItemAtIndexPath:currentIndexPath];
                }
                
                self.selectedItemIndexPath = nil;
                self.currentViewCenter = CGPointZero;
                
                UICollectionViewLayoutAttributes *layoutAttributes = [self layoutAttributesForItemAtIndexPath:currentIndexPath];
                
                __weak typeof(self) weakSelf = self;
                [UIView
                 animateWithDuration:0.3
                 delay:0.0
                 options:UIViewAnimationOptionBeginFromCurrentState
                 animations:^{
                     __strong typeof(self) strongSelf = weakSelf;
                     if (strongSelf) {
                         strongSelf.currentView.transform = CGAffineTransformMakeScale(1.0f, 1.0f);
                         strongSelf.currentView.center = layoutAttributes.center;
                     }
                 }
                 completion:^(BOOL finished) {
                     __strong typeof(self) strongSelf = weakSelf;
                     if (strongSelf) {
                         [strongSelf.currentView removeFromSuperview];
                         strongSelf.currentView = nil;
                         [strongSelf invalidateLayout];
                         
                         if ([strongSelf.delegate respondsToSelector:@selector(collectionView:layout:didEndDraggingItemAtIndexPath:)]) {
                             [strongSelf.delegate collectionView:strongSelf.collectionView layout:strongSelf didEndDraggingItemAtIndexPath:currentIndexPath];
                         }
                     }
                 }];
            }
        } break;
            
        default: break;
    }
}

- (void)calculateAllowedZone{
    // calculated based on Y, assuming that collectioView will move only vertically.
    __block CGRect topHeader = CGRectZero;
    __block NSInteger maximumIndex = 0;
    [self.headerSections enumerateObjectsUsingBlock:^(NSDictionary *header, NSUInteger idx, BOOL *stop) {
        if (self.selectedItemIndexPath.section == ((NSIndexPath*)header[@"indexPath"]).section) {
            topHeader = ((NSValue*)header[@"frame"]).CGRectValue;
        }
        if (((NSIndexPath*)header[@"indexPath"]).section > maximumIndex) {
            maximumIndex =((NSIndexPath*)header[@"indexPath"]).section;
        }
    }];
    if (self.selectedItemIndexPath.section+1 <= maximumIndex) {
        __block CGRect bottomHeader = CGRectZero;
        [self.headerSections enumerateObjectsUsingBlock:^(NSDictionary *header, NSUInteger idx, BOOL *stop) {
            if (self.selectedItemIndexPath.section+1 == ((NSIndexPath*)header[@"indexPath"]).section) {
                bottomHeader = ((NSValue*)header[@"frame"]).CGRectValue;
            }
        }];
        self.allowedZone = CGRectMake(CGRectGetMinX(topHeader), CGRectGetMinY(topHeader), CGRectGetMaxX(topHeader), CGRectGetMinY(bottomHeader));
    }else{
        __block float lastCellInSectionY = 0;
        [self.collectionView.visibleCells enumerateObjectsUsingBlock:^(UICollectionViewCell *cell, NSUInteger idx, BOOL *stop) {
            if ((cell.frame.origin.y + cell.frame.size.height) > lastCellInSectionY) {
                lastCellInSectionY = cell.frame.origin.y + cell.frame.size.height;
            }
        }];
        self.allowedZone = CGRectMake(CGRectGetMinX(topHeader), CGRectGetMinY(topHeader), CGRectGetMaxX(topHeader),CGRectGetMinY(topHeader)+lastCellInSectionY);
    }
}

- (void)setHeadersCount:(UICollectionViewLayoutAttributes*)layoutAttributes{
    
    __block NSDictionary *newheader = [NSDictionary dictionaryWithObjects:@[[NSValue valueWithCGRect:layoutAttributes.frame],layoutAttributes.indexPath]forKeys:@[@"frame",@"indexPath"]];
    __block BOOL exist = NO;
    __weak typeof(self)weakSelf = self;
   
    BOOL (^headerExist)(NSMutableArray*,NSDictionary*) = ^BOOL(NSMutableArray *headerSections, NSDictionary *newheader){
        __strong typeof(self)strongSelf = weakSelf;
        exist = NO;
        [strongSelf.headerSections enumerateObjectsUsingBlock:^(NSDictionary *header, NSUInteger idx, BOOL *stop) {
            if (((NSIndexPath*)header[@"indexPath"]).section == ((NSIndexPath*)newheader[@"indexPath"]).section) {
                exist = YES;
                *stop = YES;
            }
        }];
        return exist;
    };
    
    if (!headerExist(self.headerSections, newheader)) {
        [self.headerSections addObject:newheader];
    }
}