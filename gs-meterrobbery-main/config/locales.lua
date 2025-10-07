-- Locales for gs-meterrobbery
-- This file contains all the text strings used in the script.

function _U(key)
    local locale = {
        -- Meter Robbery
        ['meter_robbery'] = 'Meter Robbery',
        ['rob_meter'] = 'Rob Meter',
        ['meter_robbed'] = 'You successfully robbed the meter!',
        ['meter_failed'] = 'You failed to rob the meter!',
        
        -- Minigame
        ['minigame_start'] = 'Attempting to break into the meter...',
        ['minigame_failed'] = 'You failed the minigame!',
        
        -- Police
        ['police_required'] = 'Not enough police in the city!',
        
        -- Items
        ['missing_item'] = 'You don\'t have the required items!',
        
        -- Dispatch
        ['dispatch_title'] = 'Meter Robbery',
        ['dispatch_desc'] = 'Someone is attempting to rob a parking meter!',
        
        -- Cooldown
        ['global_cooldown'] = 'Meters are being watched closely right now. Try again later!',
        ['player_cooldown'] = 'You need to wait before attempting another meter robbery!',
        ['meter_cooldown'] = 'This meter was recently robbed and is empty. Try another one!',
        ['cooldown_remaining'] = 'You need to wait %s more seconds before robbing again.'
    }
    
    return locale[key] or key
end