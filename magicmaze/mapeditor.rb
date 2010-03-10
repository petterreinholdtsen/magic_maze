############################################################
# Magic Maze - a simple and low-tech monster-bashing maze game.
# Copyright (C) 2008-2010 Kent Dahl
#
# This game is FREE as in both BEER and SPEECH. 
# It is available and can be distributed under the terms of 
# the GPL license (version 2) or alternatively 
# the dual-licensing terms of Ruby itself.
# Please see README.txt and COPYING_GPL.txt for details.
############################################################

require 'magicmaze/graphics'
require 'magicmaze/map'
require 'magicmaze/gameloop'



module MagicMaze

  module MapEditor
  ########################################
  # 
  class EditorLoop < GameLoop
    
    def initialize( game_config, level = 1, player_status = nil )
      @game_config = game_config
      @graphics    = game_config.graphics
      @sound       = game_config.sound
      @input = @game_input  = Input::Control.new( self, :in_game )
      @game_delay  = 50
      @level = level
      @restart_status = player_status

      @map = nil
      @player = nil
    end


    def start(filename = nil)
      @graphics.clear_screen
      filename ||= choose_level_to_load
      if filename then
	load_map_file( filename )
      else
	return
      end
      game_loop
    end

    def choose_level_to_load
      menu_items = [
	Dir["data/maps/mm_map.*"],
	# Dir[@savedir+"/*.map"]
      ]
      menu_items.flatten!
      menu_items.sort!
      menu_items.push "Exit"

      selection = @graphics.choose_from_menu( menu_items.flatten, @input )
      if selection == "Exit" then
	selection=nil
      end
      return selection
    end

    def load_map_file(filename)
      # if @map then maybe_save end'
      @filemap = MagicMaze::FileMap.new(filename)
      @map = @filemap.to_gamemap
      @player = DungeonMaster.new( @map, self )
    end

    def save_map_file
    end
    
    
    def process_entities
      alive = @player.action_tick
      game_data = { 
        :player_location => @player.location
      }
      # @map.active_entities.each_tick( game_data )
    end

    def start_editor_loop
      puts "Editor loop..."  
      @graphics.put_screen( :background, false, false )
      draw_now      
      @graphics.fade_in

      @state = :game_loop
      while @state == :game_loop

        draw_now

        @movement = 0
        @input.check_input
        calc_movement
        
      end
    end
    
  end # EditorLoop
  
  
  class DungeonMaster < Player
    DM_SPELL_NAMES = {
      :primary => [:spell_lightning, :spell_bigball, :spell_coolcube],
      :secondary => DEFAULT_MONSTER_TILES.keys # [:spell_heal, :spell_summon_mana, :spell_magic_map, :spell_spy_eye]
    }

    DM_CREATE_SPELL_TILES = {
      :spell_lightning => AttackSpellTile.new( 10, 1,  4),
      :spell_bigball   => AttackSpellTile.new( 11, 2,  9),
      :spell_coolcube  => AttackSpellTile.new( 12, 4, 20),
    }

    DM_SUMMON_SPELL_TILES = DEFAULT_MONSTER_TILES #.values
    
    def initialize( map, game_config, *args )
      super( map, game_config, *args )
      newlocation = SpiritualLocation.new( self, map, @location.x, @location.y )
      @location = newlocation
      @primary_spell = DM_CREATE_SPELL_TILES[:spell_lightning]
      @secondary_spell = DM_SUMMON_SPELL_TILES[DM_SUMMON_SPELL_TILES.keys.first]
      @spellbook = SpellBook.new( DM_CREATE_SPELL_TILES, DM_SUMMON_SPELL_TILES , DM_SPELL_NAMES )
    end
    def move_forward( *args )
      @location.add!( @direction )
    end
    def action_tick( *args )      
      follow_impulses      
      check_counters
    end
    
    def follow_impulses
      mf = @impulses[:move_forward]
      ta = @impulses[:turn_around]
      IMPULSES.each{|key|
        value = @impulses[key]
        if value then
          self.send(key, value)
          @impulses[key] = nil
          @last_action = key
        end
      }
    end
    
    def sprite_id
      ( @override_sprite || (@direction.value+26) )
    end

  end
  
  
    ### Default Spells in Spellbook ===


  
  end # MapEditor

end # MagicMaze
