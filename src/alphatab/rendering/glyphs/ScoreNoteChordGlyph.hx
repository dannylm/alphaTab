/*
 * This file is part of alphaTab.
 * Copyright c 2013, Daniel Kuschny and Contributors, All rights reserved.
 * 
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3.0 of the License, or at your option any later version.
 * 
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library.
 */
package alphatab.rendering.glyphs;

import alphatab.model.Beat;
import alphatab.model.Note;
import alphatab.model.Voice;
import alphatab.platform.ICanvas;
import alphatab.platform.model.Color;
import alphatab.rendering.Glyph;
import alphatab.rendering.RenderingResources;
import alphatab.rendering.ScoreBarRenderer;
import alphatab.rendering.utils.BeamingHelper;
import haxe.ds.IntMap;
import haxe.ds.StringMap;

typedef ScoreNoteGlyphInfo = {
    glyph:Glyph,
    line:Int
};

class ScoreNoteChordGlyph extends Glyph
{
    private var _infos:Array<ScoreNoteGlyphInfo>;
    private var _noteLookup:IntMap<Glyph>;
    private var _tremoloPicking:Glyph;
    
    public var minNote:ScoreNoteGlyphInfo;
    public var maxNote:ScoreNoteGlyphInfo;
    
    public var spacingChanged:Void->Void;
    public var upLineX:Int;
    public var downLineX:Int;
    
    public var beatEffects:StringMap<Glyph>;
    
    public var beat:Beat;
    public var beamingHelper:BeamingHelper;

    
    public function new(x:Int = 0, y:Int = 0)
    {
        super(x, y);
        _infos = new Array<ScoreNoteGlyphInfo>();
        beatEffects = new StringMap<Glyph>();
        _noteLookup = new IntMap<Glyph>();
    }
    
    public inline function getDirection() : BeamDirection
    {
        return beamingHelper.getDirection();
    }    
    
    public function getNoteX(note:Note, onEnd:Bool = true) 
    {
        if (_noteLookup.exists(note.string)) 
        {
            var n = _noteLookup.get(note.string);
            var pos = x + n.x;
            if (onEnd) 
            {
                pos += n.width;
            }
            return pos;
        }
        return 0;
    }
    
    public function getNoteY(note:Note) 
    {
        if (_noteLookup.exists(note.string)) 
        {
            return y + _noteLookup.get(note.string).y;
        }
        return 0;
    }
       
    public function addNoteGlyph(noteGlyph:Glyph, note:Note, noteLine:Int)
    {
        var info:ScoreNoteGlyphInfo =  { glyph:noteGlyph, line:noteLine }
        _infos.push( info );
        _noteLookup.set(note.string, noteGlyph);
        if (minNote == null || minNote.line > info.line)
        {
            minNote = info;
        }
        if (maxNote == null || maxNote.line < info.line)
        {
            maxNote = info;
        }
    }
       
    public override function canScale():Bool 
    {
        return false;
    }
    
    public function updateBeamingHelper(cx:Int) : Void
    { 
        beamingHelper.registerBeatLineX(beat, cx + x + upLineX, cx + x + downLineX); 
    }
    
    public function hasTopOverflow() : Bool
    {
        return minNote != null && minNote.line < 0;
    }
    
    public function hasBottomOverflow() : Bool
    {
        return maxNote != null && maxNote.line > 8;
    }
    
    public override function doLayout():Void 
    {
        _infos.sort( function(a, b) {
            if (a.line == b.line) return 0;
            else if (a.line < b.line) return 1;
            else return -1;
        });
        
        var padding = 0; // Std.int(4 * getScale());

        var displacedX = 0;
        
        var lastDisplaced = false;
        var lastLine = 0; 
        var anyDisplaced = false; 
        
        var w = 0;
        for (i in 0 ... _infos.length)
        {
            var g = _infos[i].glyph;
             g.renderer = renderer;
            g.doLayout();
            
            g.x = padding;
           
            if (i == 0)
            {
                displacedX = g.width + padding;
            }
            else 
            {
                // check if note needs to be repositioned
                if (Math.abs(lastLine - _infos[i].line) <= 1)
                {
                    // reposition if needed
                    if (!lastDisplaced)
                    {
                        g.x = Std.int(displacedX - (getScale()));
                        anyDisplaced = true;
                        lastDisplaced = true; // let next iteration know we are displace now
                    }
                    else
                    {
                        lastDisplaced = false;  // let next iteration know that we weren't displaced now
                    }
                }
                else // offset is big enough? no displacing needed
                {
                    lastDisplaced = false;
                }
            }
            
            lastLine = _infos[i].line;
            w = Std.int(Math.max(w, g.x + g.width));
        }
        
        if (anyDisplaced)
        {
            upLineX = displacedX;
            downLineX = displacedX;
        }
        else
        {
            upLineX = w;
            downLineX = padding;
        }

        for (e in beatEffects)
        {
            e.renderer = renderer;
            e.doLayout();
        }
        
        if (beat.isTremolo())
        {
            var direction = beamingHelper.getDirection();
            var offset:Int;
            var baseNote = direction == Up ? minNote : maxNote;
            var tremoloX = direction == Up ? displacedX : 0;
            switch(beat.tremoloSpeed)
            {
                case ThirtySecond: offset = direction == Up ? -15 : 10;
                case Sixteenth: offset = direction == Up ? -12 : 10;
                case Eighth: offset = direction == Up ? -10 : 10;
                default: offset = direction == Up ? -15 : 15;
            }
            
            _tremoloPicking = new TremoloPickingGlyph(tremoloX, baseNote.glyph.y + Std.int(offset * getScale()), beat.tremoloSpeed);
            _tremoloPicking.renderer = renderer;
            _tremoloPicking.doLayout();
        }
        
        width = w + padding;
        
    }
    
    public override function paint(cx:Int, cy:Int, canvas:ICanvas):Void 
    {        
        var scoreRenderer:ScoreBarRenderer = cast renderer;
               
        //
        // Note Effects only painted once
        //
        var effectY = beamingHelper.getDirection() == Up 
                        ? scoreRenderer.getScoreY(maxNote.line, Std.int(1.5 * NoteHeadGlyph.noteHeadHeight))
                        : scoreRenderer.getScoreY(minNote.line, Std.int( -1.0 * NoteHeadGlyph.noteHeadHeight));
         // TODO: take care of actual glyph height
        var effectSpacing:Int = (beamingHelper.getDirection() == Up) 
                        ? Std.int(7 * getScale()) 
                        : Std.int( -7 * getScale());
        for (g in beatEffects)
        {
            g.y = effectY;
            g.x = Std.int(width / 2);
            g.paint(cx + x, cy + y, canvas);
            effectY += effectSpacing;
        }
        
        canvas.setColor(renderer.getLayout().renderer.renderingResources.staveLineColor);

        // TODO: Take care of beateffects in overflow
        
        var linePadding = Std.int(3 * getScale());
        if (hasTopOverflow()) 
        {
            var l = -1;
            while (l >= minNote.line)
            {
                // + 1 Because we want to place the line in the center of the note, not at the top
                var lY = cy + y + scoreRenderer.getScoreY(l + 1, -1);
                canvas.beginPath();
                canvas.moveTo(cx + x - linePadding, lY);
                canvas.lineTo(cx + x + width + linePadding, lY);
                canvas.stroke();
                l -= 2;
            }
        }
      
        if (hasBottomOverflow()) 
        {
            var l = 11;
            while (l <= maxNote.line)
            {
                var lY = cy + y + scoreRenderer.getScoreY(l + 1, -1);
                canvas.beginPath();
                canvas.moveTo(cx + x - linePadding, lY);
                canvas.lineTo(cx + x + width + linePadding, lY);
                canvas.stroke();
                l += 2;
            }
        }
        
        if(_tremoloPicking != null)
            _tremoloPicking.paint(cx + x, cy + y, canvas);
        for (g in _infos)
        {
            g.glyph.renderer = renderer;
            g.glyph.paint(cx + x, cy + y, canvas);
        }
    }    
}