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
    private var _smoothMonitor:SmoothMonitor;

    public function AdaptiveSegmentDispatcher(manifest:ManifestHandler, bandwidthMonitor:BandwidthMonitor, smoothMonitor:SmoothMonitor) {
        _manifest = manifest;
        _bandwidthMonitor = bandwidthMonitor;
        _smoothMonitor = smoothMonitor;
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

        var index:int = 0;

        for (var i:uint = 0; i < representations.length; i++) {
            if (_bandwidthMonitor.userBandwidth >= representations[i].bandwidth) {
                index = i;
            } else {
                break;
            }
        }

        index -= _smoothMonitor.fix;
        if (index < 0) {
            index = 0;
        }


        index = getManualQuality(index);

        //index = 0;
        //Console.js("calculated quality ", index, representations[index].id);
        /*Console.js("qetQuality", qualityName, representations[index].bandwidth);
         if (index != oldIndex) {
         Console.js("Downgrade quality, originalBandwidth='" + representations[oldIndex].bandwidth
         + "', newBandwidth='" + representations[index].bandwidth + "'");
         }*/

        return representations[index];
    }

    var x;

    public function getManualQuality(defaultQualityIndex) {
        var index = defaultQualityIndex;
        try {
            var qualityIndex = ExternalInterface.call('qetQuality');

            if (qualityIndex != -1) {
                index = qualityIndex;

                if (index != x) {
                    Console.js(index);
                    x = index;
                }

            }
        } catch (e) {
        }

        return index;
    }
}
}
