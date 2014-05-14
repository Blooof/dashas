/*
 * Copyright (c) 2014 castLabs GmbH
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

package com.castlabs.dash.descriptors.index {
import com.castlabs.dash.descriptors.segments.DataSegment;
import com.castlabs.dash.descriptors.segments.MediaDataSegment;
import com.castlabs.dash.descriptors.segments.ReflexiveSegment;
import com.castlabs.dash.descriptors.segments.Segment;
import com.castlabs.dash.handlers.IndexSegmentHandler;
import com.castlabs.dash.handlers.MediaSegmentHandler;
import com.castlabs.dash.utils.Console;

import flash.utils.ByteArray;

public class SegmentRange implements SegmentIndex {
    private var _baseUrl:String;
    private var _indexRange:String;
    private var _initializationRange:String;
    private var _indexSegmentHandler:IndexSegmentHandler;

    public function SegmentRange(representation:XML) {
        _baseUrl = traverseAndBuildBaseUrl(representation);
        _indexRange = traverseAndBuildIndexRange(representation);
        _initializationRange = traverseAndBuildInitializationRange(representation);
    }

    public function getInitializationSegment(representationId:String, bandwidth:Number, baseUrl:String, internalRepresentationId:Number):Segment {
        return new DataSegment(internalRepresentationId, baseUrl + _baseUrl, _initializationRange);
    }

    public function getIndexSegment(representationId:String, bandwidth:Number, baseUrl:String, internalRepresentationId:Number):Segment {
        return new ReflexiveSegment(internalRepresentationId, baseUrl + _baseUrl, _indexRange, onIndexSegmentLoaded);
    }

    public function getSegment(timestamp:Number, representationId:String, bandwidth:Number, baseUrl:String, duration:Number, internalRepresentationId:Number):Segment {
        var index:Number = calculateIndex(timestamp);

        if (index < 0 || index >= _indexSegmentHandler.references.length) {
            return null;
        }

        var reference:Object = _indexSegmentHandler.references[index];

        var range = reference.range;
        var startTimestamp = reference.startTimestamp;
        var endTimestamp = reference.endTimestamp;
        var timeOffset = reference.timeOffset;

        /* var fragmentsOfSegment = FRAGMENTS_BY_SEGMENT[index];
         if (fragmentsOfSegment) {
         //Console.js(JSON.stringify(fragmentsOfSegment));
         fragmentsOfSegment.forEach(function (segmentMetadata) {
         Console.js(segmentMetadata.timeFrom, timestamp, segmentMetadata.timeTo);
         if (segmentMetadata.timeFrom < timestamp && segmentMetadata.timeTo > timestamp) {
         var firstMoofOffset = int(_indexSegmentHandler.references[0].range.split('-')[0]);
         var lastFragment:Object = fragmentsOfSegment[fragmentsOfSegment.length - 1];

         range = (segmentMetadata.from+firstMoofOffset) + "-" + (firstMoofOffset+lastFragment.to - 1);
         startTimestamp = segmentMetadata.timeFrom;
         endTimestamp = lastFragment.timeTo;
         }
         });
         }*/

        return new MediaDataSegment(internalRepresentationId, baseUrl + _baseUrl, range, startTimestamp, endTimestamp, timeOffset);
    }

    public function update(xml:XML):void {
    }

    private function calculateIndex(timestamp:Number):Number {
        var references:Vector.<Object> = _indexSegmentHandler.references;
        for (var i:uint = 0; i < references.length; i++) {
            if (timestamp < references[i].endTimestamp) {
                return i;
            }
        }

        return -1;
    }

    public function onIndexSegmentLoaded(bytes:ByteArray):void {
        var match:Array = _indexRange.match(/([\d.]+)-/);
        var begin:Number = match ? Number(match[1]) : 0;

        Console.getInstance().debug("Creating index segment...");

        _indexSegmentHandler = new IndexSegmentHandler(bytes, begin);

        Console.getInstance().debug("Created index segment, " + _indexSegmentHandler.toString());
    }

    private static function traverseAndBuildBaseUrl(node:XML):String {
        if (node == null) {
            throw Console.getInstance().logError(new Error("Couldn't find any 'BaseURL' tag"));
        }

        if (node.BaseURL.length() == 1) {
            return node.BaseURL;
        }

        // go up one level in hierarchy, e.g. adaptionSet and period
        return traverseAndBuildBaseUrl(node.parent());
    }

    private static function traverseAndBuildIndexRange(node:XML):String {
        if (node == null) {
            throw Console.getInstance().logError(new Error("Couldn't find any 'indexRange' attribute"));
        }

        if (node.SegmentBase.length() == 1 && node.SegmentBase.hasOwnProperty("@indexRange")) {
            return node.SegmentBase.@indexRange.toString();
        }

        // go up one level in hierarchy, e.g. adaptionSet and period
        return traverseAndBuildIndexRange(node.parent());
    }

    private static function traverseAndBuildInitializationRange(node:XML):String {
        if (node == null) {
            throw Console.getInstance().logError(new Error("Couldn't find any 'range' attribute"));
        }

        if (node.SegmentBase.length() == 1
                && node.SegmentBase.Initialization.length() == 1
                && node.SegmentBase.Initialization.hasOwnProperty("@range")) {
            return node.SegmentBase.Initialization.@range.toString();
        }

        // go up one level in hierarchy, e.g. adaptionSet and period
        return traverseAndBuildInitializationRange(node.parent());
    }

    public function toString():String {
        return "baseUrl='" + _baseUrl + ", initializationRange='" + _initializationRange + "', indexRange='"
                + _indexRange + "'";
    }
}
}
