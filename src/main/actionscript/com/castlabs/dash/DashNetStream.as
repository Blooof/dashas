/*
 * Copyright (c) 2014 castLabs GmbH
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

package com.castlabs.dash {
import com.castlabs.dash.descriptors.segments.MediaDataSegment;
import com.castlabs.dash.events.FragmentEvent;
import com.castlabs.dash.events.SegmentEvent;
import com.castlabs.dash.events.StreamEvent;
import com.castlabs.dash.handlers.ManifestHandler;
import com.castlabs.dash.loaders.FragmentLoader;
import com.castlabs.dash.utils.Console;
import com.castlabs.dash.utils.Console;

import flash.events.NetStatusEvent;
import flash.events.TimerEvent;
import flash.external.ExternalInterface;
import flash.net.NetConnection;
import flash.net.NetStream;
import flash.net.NetStreamAppendBytesAction;
import flash.utils.ByteArray;
import flash.utils.Timer;
import flash.utils.setTimeout;

import org.osmf.net.NetStreamCodes;

public class DashNetStream extends NetStream {
    public static var MIN_BUFFER_TIME:Number;
    private static var MAX_BUFFER_TIME:Number;
    private static var MAX_CACHE_TIME:Number;

    // actions
    private const PLAY:uint = 1;
    private const PAUSE:uint = 2;
    private const RESUME:uint = 3;
    private const STOP:uint = 4;
    private const SEEK:uint = 5;
    private const BUFFER:uint = 6;

    // states
    private const PLAYING:uint = 1;
    private const BUFFERING:uint = 2;
    private const SEEKING:uint = 3;
    private const PAUSED:uint = 4;
    private const STOPPED:uint = 5;

    private var _state:uint = STOPPED;

    private var _loader:FragmentLoader;

    private var _loaded:Boolean = false;

    private var _offset:Number = 0;
    private var _loadedTimestamp:Number = 0;
    private var _cachedTimestamp = 0;
    private var _duration:Number = 0;
    private var _live:Boolean;

    private var _bufferTimer:Timer;
    private var _fragmentTimer:Timer;

    public function DashNetStream(connection:NetConnection) {
        super(connection);

        addEventListener(NetStatusEvent.NET_STATUS, onNetStatus);

        _bufferTimer = new Timer(350);
        _bufferTimer.addEventListener(TimerEvent.TIMER, onBufferTimer);

        _fragmentTimer = new Timer(250); // 250 ms
        _fragmentTimer.addEventListener(TimerEvent.TIMER, onFragmentTimer);
    }

    override public function play(...rest):void {
        super.play(null);


        notifyPlayStart();

        _bufferTimer.start();

        jump();

        updateState(PLAY);

        appendBytesAction(NetStreamAppendBytesAction.RESET_BEGIN);
        appendFileHeader();

    }

    private function onBufferTimer(timerEvent:TimerEvent):void {
        var bufferTime:Number = _cachedTimestamp - time;

        //Console.js(bufferTime);

        /*switch (_state) {
            case PLAYING:
                if (!_loaded && bufferTime - MIN_BUFFER_TIME < 0) {
                    //pause();
                    notifyBufferEmpty();
                    updateState(BUFFER);
                    return;
                }
                break;
            case BUFFERING:
                if (bufferTime >= MIN_BUFFER_TIME) {
                    resume();
                    notifyBufferFull();
                    return;
                }
                break;
        }*/


        if (bufferTime >= MIN_BUFFER_TIME) {
            notifyBufferFull();
            updateState(BUFFER);
        } else if(!_loaded){
            resume();
            notifyBufferEmpty();
        }

    }

    override public function pause():void {
        super.pause();
        updateState(PAUSE);
    }

    override public function resume():void {
        switch (_state) {
            case PAUSED:
            case BUFFERING:
                super.resume();
                break;
            case STOPPED:
                play();
                break;
            case SEEKING:
                jump();
                break;
        }

        updateState(RESUME);
    }

    override public function seek(offset:Number):void {
        //Console.js('seek state', _state);
        switch (_state) {
            case PAUSED:
            case STOPPED:
            case SEEKING:
                _fragmentTimer.stop();
                _loader.close();
                _offset = offset;
                super.seek(_offset);
                break;
            case PLAYING:
            case BUFFERING:
                _fragmentTimer.stop();
                _loader.close();
                _offset = offset;
                super.seek(_offset);
                jump();
                break;
        }

        updateState(SEEK);

        _cachedTimestamp = _loadedTimestamp;
    }

    override public function get time():Number {
        return super.time + _offset;
    }

    override public function close():void {
        super.close();

        appendBytesAction(NetStreamAppendBytesAction.END_SEQUENCE);
        appendBytesAction(NetStreamAppendBytesAction.RESET_SEEK);

        _bufferTimer.stop();

        notifyPlayStop();

        reset();

        updateState(STOP);
    }

    override public function get bytesLoaded():uint {
        if (_live) {
            return 1;
        } else {
            if (_loadedTimestamp == 0) {

                //WORKAROUND ScrubBar:531 ignores zero value
                return 1;
            }

            // seconds
            return _cachedTimestamp;
        }
    }

    override public function get bytesTotal():uint {
        if (_live) {
            return 1;
        } else {
            if (_loadedTimestamp == 0) {

                //WORKAROUND ScrubBar:531 ignore zero value; generate smallest possible fraction
                return uint.MAX_VALUE;
            }

            // seconds
            return _duration;
        }
    }

    public function set manifest(manifest:ManifestHandler):void {
        _live = manifest.live;
        _duration = manifest.duration;

        MIN_BUFFER_TIME = Math.min(2, _duration);

        //MAX_BUFFER_TIME = Math.min(20, _duration);
        MAX_BUFFER_TIME = Math.max(180, Math.floor(_duration / 7));
        MAX_CACHE_TIME = Math.max(180, Math.floor(_duration / 7));

        _loader = Factory.createFragmentLoader(manifest);
        _loader.addEventListener(StreamEvent.READY, onReady);
        _loader.addEventListener(FragmentEvent.LOADED, onLoaded);
        _loader.addEventListener(StreamEvent.END, onEnd);
        _loader.addEventListener(SegmentEvent.ERROR, onError);
        _loader.init();
    }


    private function appendFileHeader():void {
        var output:ByteArray = new ByteArray();
        output.writeByte(0x46);	// 'F'
        output.writeByte(0x4c); // 'L'
        output.writeByte(0x56); // 'V'
        output.writeByte(0x01); // version 0x01

        var flags:uint = 0;

        flags |= 0x01;

        output.writeByte(flags);

        var offsetToWrite:uint = 9; // minimum file header byte count

        output.writeUnsignedInt(offsetToWrite);

        var previousTagSize0:uint = 0;

        output.writeUnsignedInt(previousTagSize0);

        appendBytes(output);
    }

    private function updateState(action:Number):void {
        switch (action) {
            case PLAY:
                Console.getInstance().debug("Received PLAY action and changed to PLAYING state");
                _state = PLAYING;
                break;
            case PAUSE:
                Console.getInstance().debug("Received PAUSE action and changed to PAUSED state");
                _state = PAUSED;
                break;
            case RESUME:
                Console.getInstance().debug("Received RESUME action and changed to PLAYING state");
                _state = PLAYING;
                break;
            case STOP:
                Console.getInstance().debug("Received STOP action and changed to STOPPED state");
                _state = STOPPED;
                break;
            case SEEK:
                switch (_state) {
                    case PAUSED:
                        Console.getInstance().debug("Received SEEK action and changed to SEEKING state");
                        _state = SEEKING;
                        break;
                    case PLAYING:
                    case BUFFERING:
                        Console.getInstance().debug("Received SEEK action and changed to PLAYING state");
                        _state = PLAYING;
                        break;
                }
                break;
            case BUFFER:
                Console.getInstance().debug("Received BUFFER action and changed to BUFFERING state");
                _state = BUFFERING;
                break;
        }
    }

    private function jump():void {
        _offset = _loader.seek(_offset);
        _loadedTimestamp = 0;
        _cachedTimestamp = 0;

        super.seek(_offset);

        appendBytesAction(NetStreamAppendBytesAction.RESET_SEEK);

        _loader.loadFirstFragment();
    }

    private function notifyPlayStart():void {
        dispatchEvent(new NetStatusEvent(NetStatusEvent.NET_STATUS, false, false,
                { code: NetStreamCodes.NETSTREAM_PLAY_START, level: "status" }));
    }

    private function notifyPlayStop():void {
        dispatchEvent(new NetStatusEvent(NetStatusEvent.NET_STATUS, false, false,
                { code: NetStreamCodes.NETSTREAM_PLAY_STOP, level: "status" }));
    }

    private function notifyPlayUnpublish():void {
        dispatchEvent(new NetStatusEvent(NetStatusEvent.NET_STATUS, false, false,
                { code: NetStreamCodes.NETSTREAM_PLAY_UNPUBLISH_NOTIFY, level: "status" }));
    }

    private function notifyBufferFull():void {
        dispatchEvent(new NetStatusEvent(NetStatusEvent.NET_STATUS, false, false,
                { code: NetStreamCodes.NETSTREAM_BUFFER_FULL, level: "status" }));
    }

    private function notifyBufferEmpty():void {
        dispatchEvent(new NetStatusEvent(NetStatusEvent.NET_STATUS, false, false,
                { code: NetStreamCodes.NETSTREAM_BUFFER_EMPTY, level: "status" }));
    }

    private function reset():void {
        _offset = 0;
        _loadedTimestamp = 0;
        _cachedTimestamp = 0;

        _loaded = false;
    }

    private function onReady(event:StreamEvent):void {
        dispatchEvent(event);
    }

    //private var lastPushedEnd = -1;

    private function onLoaded(event:FragmentEvent):void {
        //if (lastPushedEnd == event.endTimestamp)return;
        //lastPushedEnd = event.endTimestamp;

        _loadedTimestamp = event.endTimestamp;

        if (_cachedTimestamp < event.endTimestamp) {
            _cachedTimestamp = event.endTimestamp;
        }

        //Console.js("pushed in stream till", event.endTimestamp);

        appendBytes(event.bytes);

        onFragmentTimer();

    }

    private function onError(event:SegmentEvent):void {
        dispatchEvent(new NetStatusEvent(NetStatusEvent.NET_STATUS, false, false,
                { code: NetStreamCodes.NETSTREAM_FAILED, level: "error" }));
    }


    /*private var lastQuality = 0;

     private function flushIfNeed() {
     try {
     var qualityVo = ExternalInterface.call('qetQuality');

     if (qualityVo.manual != -1 && qualityVo.manual > lastQuality) {
     _cachedTimestamp = _loadedTimestamp;
     lastQuality = qualityVo.manual;
     //_fragmentTimer.start();
     }

     } catch (e) {
     }
     }*/

    private function onFragmentTimer(timerEvent:TimerEvent = null):void {
        _fragmentTimer.stop();
        if ((_loadedTimestamp - time) < MAX_BUFFER_TIME) {
            _loader.loadNextFragment();
        } else {
            _fragmentTimer.start();

            /*flushIfNeed();

             if ((_cachedTimestamp - time) < MAX_CACHE_TIME) {
             _loader.cacheNextFragment(_cachedTimestamp, function (e):void {
             _cachedTimestamp = e.segment.endTimestamp;

             Console.js('cache request', e.segment.startTimestamp + '-' + e.segment.endTimestamp);
             _fragmentTimer.start();
             });
             } else {
             _fragmentTimer.start();
             }*/
        }
    }

    public function get currentQuality():Number {
        var _currentQuality = 0;
        try {
            _currentQuality = _loader.getIndexById(_loader.getVideoSegment(time).representationId);
        } catch (e) {
        }
        return _currentQuality
    }

    private function onNetStatus(event:NetStatusEvent):void {

        switch (event.info.code) {
            case NetStreamCodes.NETSTREAM_BUFFER_EMPTY:
                if (_loaded) {
                    close();
                    notifyPlayUnpublish();
                }
                break;
            case NetStreamCodes.NETSTREAM_PLAY_STREAMNOTFOUND:
                close();
                break;
        }
    }

    private function onEnd(event:StreamEvent):void {
        _loaded = true;
        _loadedTimestamp = _duration;
        _cachedTimestamp = _duration;
    }
}
}
