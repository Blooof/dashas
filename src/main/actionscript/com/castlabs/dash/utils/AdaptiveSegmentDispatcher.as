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
    public var _oldIndex:int = -1;

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

        var newIndex:int = _oldIndex;
        while (true) {
            if (newIndex < 0 || newIndex >= representations.length) {
                break;
            } else if (_bandwidthMonitor.userBandwidth < representations[newIndex].bandwidth) {
                newIndex--;
            } else if (newIndex < representations.length - 1 &&
                    _bandwidthMonitor.userBandwidth > representations[newIndex + 1].bandwidth * 1.4) {
                newIndex++;
            } else {
                break;
            }
        }

        try {
            var qualityVo = ExternalInterface.call('qetQuality');
            if (qualityVo.manual == -1) {
                if (_oldIndex == -1) {
                    newIndex = qualityVo.suggest || 0;
                    //Console.js('123', newIndex);

                }
            } else {
                newIndex = qualityVo.manual;
            }

        } catch (e) {
        }

        //Console.js(newIndex);

        _oldIndex = newIndex;

        //newIndex = 3;

        if (newIndex < 0) newIndex = 0;
        if (newIndex > representations.length - 1) newIndex = representations.length - 1;

        return representations[newIndex];
    }

}
}
