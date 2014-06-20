/*
 * Copyright (c) 2014 castLabs GmbH
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

package com.castlabs.dash.utils {
import com.castlabs.dash.descriptors.Representation;
import com.castlabs.dash.descriptors.segments.Segment;
import com.castlabs.dash.handlers.ManifestHandler;

import flash.external.ExternalInterface;

public class AdaptiveSegmentDispatcher {
    private var _manifest:ManifestHandler;
    private var _bandwidthMonitor:BandwidthMonitor;
    private var _oldIndex:uint = 0;

    public function AdaptiveSegmentDispatcher(manifest:ManifestHandler, bandwidthMonitor:BandwidthMonitor) {
        _manifest = manifest;
        _bandwidthMonitor = bandwidthMonitor;
    }

    public function getVideoSegment(timestamp:Number):Segment {
        return findOptimalRepresentation(_manifest.videoRepresentations).getSegment(timestamp);
    }

    public function getVideoSegmentByIndex(index:int, timestamp:Number):Segment {
        return _manifest.videoRepresentations[index].getSegment(timestamp);
    }

    public function getIndexById(index):Number {
        for (var i:uint = 0; i < _manifest.videoRepresentations.length; i++) {
            if (int(_manifest.videoRepresentations[i].id) == index) {
                return i;
            }
        }
        return 0;
    }

    private function findOptimalRepresentation(representations:Vector.<Representation>):Representation {
        if (representations.length == 0) {
            return null;
        }

        var newIndex:uint = _oldIndex;
        while (true) {
            if (newIndex < 0 || newIndex > representations.length) {
                break;
            } else if (_bandwidthMonitor.userBandwidth < representations[newIndex].bandwidth && newIndex > 0) {
                newIndex--;
            } else if (newIndex < representations.length - 1 && _bandwidthMonitor.userBandwidth > representations[newIndex + 1].bandwidth * 1.1) {
                newIndex++;
            } else {
                break;
            }
        }


        newIndex = getManualQuality(newIndex);
        return representations[newIndex];
    }

    public function getManualQuality(defaultQualityIndex) {
        var index = defaultQualityIndex;
        try {
            var qualityIndex = ExternalInterface.call('qetQuality');

            if (qualityIndex != -1) {
                index = qualityIndex;
            }
        } catch (e) {
        }

        return index;
    }
}
}
