//
//  kflHTLPManager.m
//  SoundScapeTK
//
//  Last revised by Thomas Stoll on 7/2/14.
//  Copyright (c) 2012-14 Kitefish Labs. All rights reserved.
//

#import "kflHTLPManager.h"
#import "PdBase.h"

#define PI 3.141592653589793
#define TWO_PI (2.0*PI)

@implementation kflHTLPManager

@synthesize scapeRegions, scapeSoundfiles; // currentActiveRegions, currentPausedRegions,
@synthesize audioFileRouter;

+ (id)sharedManager {
    static kflHTLPManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (id) init {

    if (self = [super init]) {
        
        [self reset];
        self.audioFileRouter = [kflAudioFileRouter audioFileRouterForPatch:@"sampler4bank.pd" withNumberOfSlots:4];
    }
    return self;    
}

- (void)killAll {
    DLog(@"kill 'em all!");
    [self processEnterAndExitEvents:[NSArray arrayWithObject:[NSNumber numberWithInt:-1]]];
    [NSThread sleepForTimeInterval:0.1];
    for (NSString *key in [self.scapeRegions allKeys]) {
        [[self.scapeRegions objectForKey:key] setState:@"ready"];
    }
}

- (void)reset {

    DLog(@"\n\n\n********RESET HTLP MANAGER*****\n\n\n");
    
    if (scapeRegions == nil) {
        scapeRegions = [NSMutableDictionary dictionaryWithCapacity:1];
    } else {
        [scapeRegions removeAllObjects];
    }
    if (scapeSoundfiles == nil) {
        scapeSoundfiles = [NSMutableDictionary dictionaryWithCapacity:1];
    } else {
        [scapeSoundfiles removeAllObjects];
    }
}


-(void) addRegion:(kflLinkedRegion *)lr forIndex:(NSNumber *)index {
    [self.scapeRegions setObject:lr forKey:index];
}

- (NSString *)hitTestRegionsWithLocation:(CGPoint)location {
    
    HTLPLog(@"SCAPE: %i", [scapeRegions count]);
    HTLPLog(@">>HIT-TESTING LOCATION: %f, %f", location.x, location.y);
    HTLPLog(@"loc x: %f y: %f", location.x, location.y);
    
    NSMutableArray *hitRegions = [NSMutableArray arrayWithCapacity:1];
    
    for (NSString *lrkey in self.scapeRegions) {
        HTLPLog(@"::: %@", [scapeRegions objectForKey:lrkey]);
        if ([[scapeRegions objectForKey:lrkey] isKindOfClass:[kflLinkedCircleSFRegion class]]) {
            
            kflLinkedCircleSFRegion *lcr = [scapeRegions objectForKey:lrkey];
//            HTLPLog(@"lr key: %@ || pt: %f, %f | rad: %f", lrkey, lcr.center.x, lcr.center.y, lcr.radius);
            float dist = sqrtf(powf((lcr.center.x - location.x), 2.0) + powf((lcr.center.y - location.y), 2.0));
            
            //HTLPLog(@"lat/lon/radius||x,y: %f, %f, %f || %f, %f", lcr.center.x, lcr.center.y, (lcr.radius+0.00001), location.x, location.y);
            
            if (dist <= (lcr.radius+0.00001)) { // && (![[self.scapeSoundfiles objectForKey:[lcr.linkedSoundfiles objectAtIndex:0]] playing])) {
                
                lcr.internalDistance = dist / lcr.radius;
                HTLPLog(@"====== circle HIT: %i ====== int. dist: %f", lcr.idNum, lcr.internalDistance);
                [hitRegions addObject:lcr];
            }
            
        } else if ([[scapeRegions objectForKey:lrkey] isKindOfClass:[kflLinkedCircleSynthRegion class]]) {
            
            kflLinkedCircleSynthRegion *lcsr = [scapeRegions objectForKey:lrkey];
            //            HTLPLog(@"lr key: %@ || pt: %f, %f | rad: %f", lrkey, lcr.center.x, lcr.center.y, lcr.radius);
            float dist = sqrtf(powf((lcsr.center.x - location.x), 2.0) + powf((lcsr.center.y - location.y), 2.0));
            
            //HTLPLog(@"lat/lon/radius||x,y: %f, %f, %f || %f, %f", lcr.center.x, lcr.center.y, (lcr.radius+0.00001), location.x, location.y);
            
            if (dist <= lcsr.radius+0.00001) {
                
                float angle = atan2f((location.y - lcsr.center.y), (location.x - lcsr.center.x));
                NSLog(@"angle----------");
                NSLog(@"angle1: %f", angle);
                
                lcsr.internalDistance = dist / lcsr.radius;
                
                angle -= (lcsr.angleOffset * PI);
                NSLog(@"angle2: %f", angle);
                
                if (angle <= -PI) {
                    angle += TWO_PI;
                }
                NSLog(@"angle3: %f", angle);
                
                angle = ABS(angle);
                NSLog(@"angle4: %f", angle);
                
                lcsr.angle = angle;
                HTLPLog(@"====== circle HIT: %i ====== int. dist: %f", lcsr.idNum, lcsr.internalDistance);
                [hitRegions addObject:lcsr];
            }
        }
    }
    HTLPLog(@"hit regions: count: %i", [hitRegions count]);
    for (kflLinkedCircleSFRegion *r in hitRegions) {
        NSLog(@"hr: %@, %@, %i", r, [[r.linkedSoundfiles objectAtIndex:0] fileName], r.idNum);
    }
    if ([hitRegions count] > 0) {
        HTLPLog(@"ACTIVE HASH AFTER hit----: %@", audioFileRouter.activeHash);
        [self processEnterAndExitEvents:hitRegions];
        return [NSString stringWithFormat:@"HIT(S): %i", [hitRegions count]];
        
    } else { // nothing hit!
        
        HTLPLog(@"ACTIVE HASH AFTER miss----: %@", audioFileRouter.activeHash);
        // if there are no hit regions, then process-enter-and-exit events with a dummy event
        [self processEnterAndExitEvents:[NSArray arrayWithObject:[NSNumber numberWithInt:-1]]];
        return @"MISS!";
    }
    return nil;

}


- (void)processEnterAndExitEvents:(NSArray *)regionList {
    
    // regionList: the list of all regions returning hits from the hit test or -1 which signals all regions to cutoff
    
    // if only one region, and idnum == -1, this is a signal to EXIT ALL REGIONS!
    // - pause playing ones according to the rule
    // - or allow playing ones to finish!
    NSLog(@" count:: %i || region list: %@", [regionList count], [regionList objectAtIndex:0]);
    
    if ([[regionList objectAtIndex:0] respondsToSelector:@selector(idNum)]) {
        HTLPLog(@" count:: %i || id num: %i", [regionList count], [[regionList objectAtIndex:0] idNum]);
    }
    if (([regionList count] == 1) && (![[regionList objectAtIndex:0] respondsToSelector:@selector(idNum)])) {
        
        // read the list of ACTIVE regions and schedule stop for all of them
        for (NSString *activeSlot in [self.audioFileRouter.activeHash allKeys]) {
            HTLPLog(@"region ID: %@", activeSlot);
            
            kflLinkedSoundfile *lsf = [self.audioFileRouter.activeHash objectForKey:activeSlot];
            kflLinkedCircleSFRegion *lcr = [self.scapeRegions objectForKey:[NSString stringWithFormat:@"%i", lsf.idNum]];
            
            // check each active region:
            //      if cutoff bit == 1, kill & remove
            //      else do nothing

            // if region.rule == 1
            int finishrule = lcr.finishRule;
            HTLPLog(@"fr: %i", finishrule);
            if ((finishrule & 1) == 0) { // let-finish bit IS NOT set

                // now stop it (also removes from activeHash!
                DLog(@"\nSTOP from COMPLETE MISS!\nrid: %@ | %i | %i", lcr, lcr.idNum, lsf.idNum);
                lcr.state = @"stop";
                [self scheduleLSFToStopForRegion:lcr];
                
            } else if (([lcr.state compare:@"playing"] == NSOrderedSame)) { // else mark region for loop-end-stop -- let-finish bit IS set; allow sound to finish
                lcr.state = @"stopRequested";
                DLog(@"STOP REQUESTED from COMPLETE MISS!");
            }
        }
        // update ALL the synth regions
        // - set ALL *_level params to 0
        
        for (NSString *lrkey in self.scapeRegions) {
            HTLPLog(@"%@", lrkey);
            id region = [self.scapeRegions objectForKey:lrkey];
            if ([region isKindOfClass:[kflLinkedCircleSynthRegion class]]) {
                kflLinkedCircleSynthRegion *lcsr = region;
                HTLPLog(@"lcsr: %@", lcsr);
                NSArray *params = lcsr.linkedParameters;
                for (kflLinkedParameter *param in params) {
                    // adjust it to 0.0 if it's a _level pararam
                    if (([param.paramName rangeOfString:@"_noise_level"].location != NSNotFound) || ([param.paramName rangeOfString:@"_pulse_level"].location != NSNotFound)) {

                        [PdBase sendFloat:0.0 toReceiver:param.paramName];
                    }
                }
                HTLPLog(@"LCSR: %@ --> ready", lcsr);
                lcsr.state = @"ready";
            }
        }
        // set master volume to 0 (global mute)
        HTLPLog(@"***MASTER VOLUME ---> 0.0!");
        [PdBase sendFloat:0.0 toReceiver:@"_master_volume"];
        
        // empty out region list and return????
        
    } else {
        
        // positive trigger events, handle the regions in the list!
        
        for (id region in regionList) {
            
            if ([region isKindOfClass:[kflLinkedCircleSFRegion class]]) {
                
                kflLinkedCircleSFRegion *lcr = region;
                //lcr = [self.scapeRegions objectForKey:[NSString stringWithFormat:@"%i", lcr.idNum]];
                
                // current state of each LR
                HTLPLog(@"LR: %i | %i | %i | %i | %i | %f", lcr.active, lcr.numLives, lcr.numLinkedSoundfiles, lcr.idNum, lcr.numLoops, lcr.internalDistance);
                HTLPLog(@"%@", lcr.linkedSoundfiles);
                
                // make sure that the region is active and that there is at least one life left
                if ((lcr.active) && (lcr.numLives > 0)) {
                    
                    kflLinkedSoundfile *lsf = [lcr.linkedSoundfiles objectAtIndex:0];
                    HTLPLog(@"LSF: : %@", lsf);
                    HTLPLog(@"state: %@", lcr.state);
                    if ([lcr.state compare:@"ready"] == NSOrderedSame) {
                        //DLog(@"%@\n%@\n", scapeSoundfiles, [scapeSoundfiles objectForKey:[[lr.linkedSoundfiles objectAtIndex:0] stringValue]]);
                        
                        HTLPLog(@"play this: %@", lsf);
                        HTLPLog(@"assign...");
                        int foundSlot = [self.audioFileRouter assignSlotForLSF:lsf];
                        HTLPLog(@"assigned to slot: %i", foundSlot);
                        if (foundSlot > -1) {
                            [self scheduleLSFToPlayForRegion:lcr afterDelay:0.f];;
                        }
                        
                        // ===== scheduleLSFToPlay should cause audiofilerouter to put this LSF/region into an active hash
                        // AND mark this LSF as @"playing"
                        
                    } else if ([lcr.state compare:@"playing"] == NSOrderedSame) {
                        // adjust the level of an already-playing LSF
                        HTLPLog(@"just adjust the level: %f for %@ + %i", MAX(1.0 - lcr.internalDistance, 0.0), lsf.fileName, lcr.idNum);
                        [self.audioFileRouter adjustVolumeForLSF:lsf to:MAX((1.0 - lcr.internalDistance), 0.0) withRampTime:1000];
                    } else {
                        HTLPLog(@"UHOH! State should have been either playing or ready");
                    }
                }
                
                //            // A region can activate other regions
                //            if (lcr.idsToActivate != nil) {
                //                DLog(@"ids TO BE ACTIVATED: %@", lcr.idsToActivate);
                //
                //                for (NSNumber *idnum in lcr.idsToActivate) {
                //                    DLog(@"setting ID #%i to ACTIVE...", [idnum intValue]);
                //                    DLog(@"before: %i : %i", [idnum intValue], [[scapeRegions objectForKey:[idnum stringValue]] active]);
                //                    [[scapeRegions objectForKey:[idnum stringValue]] setActive:YES];
                //                    DLog(@"after: %i : %i", [idnum intValue], [[scapeRegions objectForKey:[idnum stringValue]] active]);
                //                }
                //                lcr.idsToActivate = nil;
                //            }

            } else if ([region isKindOfClass:[kflLinkedCircleSynthRegion class]]) {
                
                kflLinkedCircleSynthRegion *lcsr = region;
                //lcr = [self.scapeRegions objectForKey:[NSString stringWithFormat:@"%i", lcr.idNum]];
                
                if (([lcsr.state compare:@"ready"] == NSOrderedSame) && (lcsr.active) && (lcsr.numLives > 0)) {
                
                    HTLPLog(@"LCSR: %@ ready --> playing", lcsr);
                    [self.audioFileRouter executeParamChangeforLCSR:lcsr];
                    lcsr.state = @"playing";
                    NSLog(@"***MASTER VOLUME ---> 1.0!");
                    [PdBase sendFloat:1.0 toReceiver:@"_master_volume"];
                    lcsr.numLives -= 1;

                } else if ([lcsr.state compare:@"playing"] == NSOrderedSame) {
                    
                    HTLPLog(@"LCSR: %@ playing --> playing", lcsr);
                    [self.audioFileRouter executeParamChangeforLCSR:lcsr];
                    
                }
            }
        }
        
        /**
         *  Step 3: done processing region list, now filter deactivated regions...
         */
        
        NSMutableArray *lsfsNotInLastRegionHit = [NSMutableArray arrayWithCapacity:1];
        
        HTLPLog(@"curr. active hash (before set-differencing): %@", self.audioFileRouter.activeHash);

        NSMutableArray *lcrsLSFs = [NSMutableArray arrayWithCapacity:1];
        
        for (id region in regionList) {

            if ([region isKindOfClass:[kflLinkedCircleSFRegion class]]) {
                kflLinkedCircleSFRegion *lcr = region;
                [lcrsLSFs addObject:[[lcr linkedSoundfiles] objectAtIndex:0]];
            }
        }
        HTLPLog(@"curr. REGIONs' LSFs list (before set-differencing): %@", lcrsLSFs);
        NSSet *lcrsLSFSet = [NSSet setWithArray:lcrsLSFs];
        // any active regions that are not in the latest region list are added to tobeDeleted
        // use audio file router's lis of active LSFs to determine the regionIDs to be stopped
        // convert activeHash from dict to array
        
        
        // iterate over the active hash and compare each to the set of all linkedregion's LSFs
        for (NSString *hashKey in [self.audioFileRouter.activeHash allKeys]) {
            kflLinkedSoundfile *activeLSF = [self.audioFileRouter.activeHash objectForKey:hashKey];
            HTLPLog(@"LSF: %@", activeLSF);
            if (![lcrsLSFSet containsObject:activeLSF]) {
                // we have an active lsf that had a region hit, so remove it from the set
                [lsfsNotInLastRegionHit addObject:activeLSF];
            }
        }
        
        HTLPLog(@"to be deleted: %@", lsfsNotInLastRegionHit);
        for (kflLinkedSoundfile *lsf in lsfsNotInLastRegionHit) {
            
            // get the lcr by looking it up by its region ID (should match)
            kflLinkedCircleSFRegion *lcr = [self.scapeRegions objectForKey:[NSString stringWithFormat:@"%i", lsf.idNum]];
            
            // if region.rule == 1
            HTLPLog(@"loop rule: %i", lcr.finishRule);
            if ((lcr.finishRule & 1) == 1) { // cutoff bit set

                // @@@ add this region/lsf to the list of paused regions with it's time offset

                HTLPLog(@"STOP from toBeDeleted!   LCR: %@", lcr);
                lcr.state = @"stop";
                [self scheduleLSFToStopForRegion:lcr];
                
            } else { // else mark region for loop-end-stop
                lcr.state = @"stopRequested";
                HTLPLog(@"STOP REQUESTED from toBeDeleted!");
            }
        }
    }
}

- (void)scheduleLSFToStopForRegion:(kflLinkedCircleSFRegion *)lcr {
    
    kflLinkedSoundfile *lsf = [lcr.linkedSoundfiles objectAtIndex:0];
    
    NSLog(@"stop this LSF: %@", lsf);
    
    __block UIBackgroundTaskIdentifier bgTaskID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler: ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (bgTaskID != UIBackgroundTaskInvalid)
            {
                [[UIApplication sharedApplication] endBackgroundTask:bgTaskID];
                bgTaskID = UIBackgroundTaskInvalid;
            }
        });
    }];
    
    if ([lcr.state compare:@"stop"] == NSOrderedSame) {
        [lsf markOffset];
    } else if ([lcr.state compare:@"stopRequested"] == NSOrderedSame) {
        // mark lsf's offset as current time - start time
        [lsf clearOffset];
    }
    
    DLog(@" ==== schedule LSF to stop...");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        //                [[LAPManager sharedManager] recordTrackingMarkerWithType:@"PLAY" andArgs:[NSArray arrayWithObject:[NSNumber numberWithInt:lsf.idNum]]];
        NSLog(@"stop region with lsfID: %i", lcr.idNum);
        [self.audioFileRouter stopLinkedSoundFileForRegion:lcr];
        
        [NSThread sleepForTimeInterval:(lsf.releaseTime * 0.001)];
        
        [self.audioFileRouter resetLinkedSoundFileForRegion:lcr];
        NSLog(@"set paused offset: %f (ID: %i)", lsf.pausedOffset, lsf.idNum);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (bgTaskID != UIBackgroundTaskInvalid)
            {
                // if you don't call endBackgroundTask, the OS will exit your app.
                [[UIApplication sharedApplication] endBackgroundTask:bgTaskID];
                bgTaskID = UIBackgroundTaskInvalid;
            }
        });
    });
    
    HTLPLog(@"ACTIVE HASH AFTER STOP: %@", self.audioFileRouter.activeHash);
    HTLPLog(@"LCR state: %@", lcr.state);
}


- (void) scheduleLSFToPlayForRegion:(kflLinkedCircleSFRegion *)lcsfr afterDelay:(NSTimeInterval)delay {
    
    kflLinkedSoundfile *lsf = [lcsfr.linkedSoundfiles objectAtIndex:0];
    
    __block UIBackgroundTaskIdentifier bgTaskID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler: ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (bgTaskID != UIBackgroundTaskInvalid)
            {
                [[UIApplication sharedApplication] endBackgroundTask:bgTaskID];
                bgTaskID = UIBackgroundTaskInvalid;
            }
        });
    }];
    
    DLog(@" ==== schedule LSF to play...");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        // HERE IS WHERE THE PLAYBACK LOGIC IS HOOKED IN...
        
        //        float duration = lsf.length;
        [NSThread sleepForTimeInterval:delay];
        
        // read out the lsf's current id number
        lsf.uniqueID = [[NSDate date] timeIntervalSince1970];
        int currentID = lsf.uniqueID;
        
        NSLog(@"generating unique ID: %i for LSF ID: %i", currentID, lsf.idNum);
        
        // default is to play the sound file until told otherwise or until max num. of loops have played
        
        if (([lcsfr.state compare:@"ready"] == NSOrderedSame) && (lsf.assignedSlot > -1) && (currentID == lsf.uniqueID)) {
            
            lcsfr.numLives -= 1;
            
            // audio file router sets state to @"playing"
            [[kflLAPManager sharedManager] recordTrackingMarkerWithType:@"PLAY" andArgs:[NSArray arrayWithObject:[NSNumber numberWithInt:lsf.idNum]]];
            [self.audioFileRouter playLinkedSoundFile:lsf
                                            forRegion:lcsfr
                                             atVolume:MAX((1.0 - lcsfr.internalDistance),0.0)];
            // DON't NEED TO KNOW OFFSET
            // not actually keeping this thread alive!
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (bgTaskID != UIBackgroundTaskInvalid)
            {
                // if you don't call endBackgroundTask, the OS will exit your app.
                [[UIApplication sharedApplication] endBackgroundTask:bgTaskID];
                bgTaskID = UIBackgroundTaskInvalid;
            }
        });
    });
}

@end