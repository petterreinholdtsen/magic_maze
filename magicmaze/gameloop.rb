require 'magicmaze/filemap'
require 'magicmaze/movement'
require 'magicmaze/player'

require 'magicmaze/graphics'

module MagicMaze

  class GameLoop

    attr_reader :graphics, :sound, :input

    def initialize( game_config, level = 1, player_status = nil )
      @game_config = game_config
      @graphics    = game_config.graphics
      @sound       = game_config.sound
      @input = @game_input  = Input::Control.new( self, :in_game )
      @game_delay  = 50
      @level = level
      @restart_status = player_status
    end
    
    def load_map( level = 1, saved = nil )
      puts "Loading level: #{level}"
      filename = level
      filename = sprintf("data/maps/mm_map.%03d",level
                         ) if level.kind_of? Numeric
      filemap = MagicMaze::FileMap.new( filename )

      @map.purge if @map # Clean up old map, if any.

      @level = level
      @map = filemap.to_gamemap
      @map_title = filemap.title

      should_reset = @player || @restart_status
      @player = Player.new( @map, self )  unless @player
      @player.reset( @map, @restart_status )  if should_reset
      @restart_status = nil


      @saved_player_status = @player.get_saved
      @game_config.update_checkpoint( level, @saved_player_status )

      GC.start
    end

    def move_up
      turn_and_move( Direction::NORTH )
    end
    def move_down
      turn_and_move( Direction::SOUTH )
    end
    def move_left
      turn_and_move( Direction::WEST )
    end
    def move_right
      turn_and_move( Direction::EAST )
    end

    def turn_and_move( dir )
      @movement |= (1<<dir.value)
    end

    def calc_movement
      # cancelation of opposite moves instead
      # of flickering like mad.
      [0b1010, 0b0101].each{|cancel|
        if @movement&cancel==cancel
          @movement^=cancel
        end
      }
      4.times{|m|
        if @movement & 1 != 0
          old_turn_and_move(m)
        end
        @movement >>=1
      }
    end

    def old_turn_and_move( dir )
      if @player.direction.value == dir
        @player.add_impulse(:move_forward)
      else
        @player.add_impulse(:turn_around, dir )
      end
    end


    ##
    # Actions
    
    def toogle_fullscreen
      @graphics.toogle_fullscreen
    end


    ##
    # Refactored block form for all actions that require verification. 
    #
    def really_do?( message )
      @graphics.show_long_message( message + "\n[Y/N]" )
      if @game_input.get_yes_no_answer
	yield
      end
    end

    def escape
      really_do?("Quit game?") do
	@state = :stopped_game
      end
    end

    def save_game
      @game_config.save_checkpoints
    end

    def pause_game
      @graphics.show_long_message( "Paused!\n\nPress any key\nto resume game." )
      @game_input.get_key_press
    end

    def increase_volume
      @sound.change_volume( 1 )
      @sound.play_sound( :bonus )
    end

    def decrease_volume
      @sound.change_volume( -1 )
      @sound.play_sound( :bonus )
    end

    def increase_speed
      @game_delay -= 5 if @game_delay > 10      
      puts "Game delay: #@game_delay"
    end

    def decrease_speed
      @game_delay += 5 if @game_delay < 100      
      puts "Game delay: #@game_delay"
    end


   def helpscreen
     @graphics.show_help
     @game_input.get_key_press
     @graphics.put_screen( :background, false, false )
    end

    def restart_level
      really_do?("Restart level?") do
	@state = :restart_level
      end
    end

    def next_primary_spell
      @player.spellbook.page_spell( :primary )
    end
    def previous_primary_spell
      @player.spellbook.page_spell( :primary, -1)
    end
    def next_secondary_spell
      @player.spellbook.page_spell( :secondary )
    end
    def previous_secondary_spell
      @player.spellbook.page_spell( :secondary, -1)
    end

    def cast_primary_spell
      primary_spell.cast_spell( @player )
    end
    def cast_alternative_spell
      secondary_spell.cast_spell( @player )
    end


    ##
    # Getters
    def primary_spell
      @player.spellbook.spell( :primary )
    end
    def secondary_spell
      @player.spellbook.spell( :secondary )
    end



    def get_score
      @player.score
    end
    def get_inventory
      @player.inventory
    end
    def get_life
      @player.life
    end
    def get_mana
      @player.mana
    end



    def game_loop
      puts "Game loop"  
      
      # Fade in the background
      @graphics.fade_in do 
	@graphics.put_screen( :background, false, false )
	draw_now
      end    

      @state = :game_loop
      while @state == :game_loop

        time_start = SDL.get_ticks

        draw_now

        @movement = 0
        @game_input.check_input
        calc_movement

        @state = catch( :state_change ) do 
          alive = @player.action_tick
	  game_data = { 
	    :player_location => @player.location
	  }
          @map.active_entities.each_tick( game_data )
          @state
        end

        time_end = SDL.get_ticks
        delay = @game_delay + time_start - time_end
        SDL.delay(delay) if delay > 0 
	# puts delay
      end
      @graphics.fade_out do  
	@graphics.put_screen( :background, false, false )
	draw_now
      end    
      @state
    end # loop
    protected :game_loop

    def start
      begin
        load_map( @level )

	# Loading message
	loading_message = "Entering level " + 
	  @level.to_s + "\n#@map_title\nGet ready!"
	@graphics.fade_in_and_out do
	  @graphics.clear_screen
	  @graphics.show_long_message(loading_message, false, :fullscreen )
	end



        game_loop
        case @state
        when :next_level  
          @level += 1 
          unless @game_config.check_level( @level ) 
            @state = :endgame
          end
	when :restart_level
	  @restart_status = @saved_player_status
        when :player_died 
          draw_now
          puts "Score: #{@player.score}"
          sleep 1
	  @restart_status = @saved_player_status
        end
      end while [:next_level,:restart_level,:player_died].include? @state
    end


    def draw_now
      draw ; @graphics.flip
    end


    def draw
      draw_maze( @player.location.x, @player.location.y )
      # @graphics.update_player( @player.direction.value )
      @graphics.update_spells(primary_spell.sprite_id, 
                              secondary_spell.sprite_id )
      @graphics.write_score( get_score ) 
      @graphics.update_life_and_mana( get_life, get_mana )
      @graphics.update_inventory( get_inventory )
    end



    def draw_maze( curr_x, curr_y )
      @graphics.update_view_rows(curr_y)do |current_y|
        @graphics.update_view_columns(curr_x)do |current_x|
          @map.each_tile_at( current_x, current_y ) do |tile|
            @graphics.update_view_block( tile.sprite_id ) if tile
          end
        end
      end
    end

    def alternative_inner_drawing
      @map.all_tiles_at( current_x, current_y ) do
        |background, object, entity, spiritual|
        # background = @map.background.get(current_x,current_y)
        @graphics.update_view_background_block( background.sprite_id )
        # object = @map.object.get(current_x,current_y)
        @graphics.update_view_block( object.sprite_id ) if object
        # entity = @map.entity.get(current_x,current_y)
        @graphics.update_view_block( entity.sprite_id ) if entity
      end
    end

      
  end # GameLoop


end # MagicMaze
