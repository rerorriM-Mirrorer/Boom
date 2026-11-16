-- Magical Blood Pact: Rage moves Boom may use to magic burst (pure table, no
-- Windower calls). Physical pacts (Poison Nails, Flaming Crush...) make
-- skillchains instead and are not listed here; Astral Flow pacts are left out.
--
-- Inferred, confirm live: these pacts can Magic Burst, and the element of each.
-- Edit freely; within an element the first usable pact wins, so stronger ones
-- come first. Element names follow Boom's burst table (Thunder, not Lightning).
local burst_pacts = {}

burst_pacts.by_element = {
    Fire    = { 'Conflag Strike', 'Meteor Strike', 'Fire IV', 'Fire II' },
    Ice     = { 'Heavenly Strike', 'Blizzard IV', 'Blizzard II' },
    Wind    = { 'Wind Blade', 'Aero IV', 'Tornado II', 'Sonic Buffet', 'Aero II' },
    Earth   = { 'Geocrush', 'Stone IV', 'Stone II' },
    Thunder = { 'Thunderstorm', 'Thunder IV', 'Thunderspark', 'Thunder II' },
    Water   = { 'Grand Fall', 'Water IV', 'Water II' },
    Light   = { 'Holy Mist', 'Meteorite', 'Level ? Holy' },
    Dark    = { 'Night Terror', 'Impact', 'Nether Blast', 'Lunar Bay' },
}

-- Status ids that stop pet commands (Trust blood_pact_rage.lua): sleep,
-- petrification, charm, terror, amnesia, invisible. Silence does not.
burst_pacts.BLOCK = { [2]=true, [19]=true, [7]=true, [14]=true, [17]=true, [28]=true, [16]=true, [69]=true, [0]=true }

burst_pacts.RANGE = 21 -- Inferred: summoner-to-mob limit, same as the coordinator uses

-- Ordered pact names for a list of chain elements.
function burst_pacts.names_for(elements)
    local list = {}
    for _, element in ipairs(elements or {}) do
        for _, name in ipairs(burst_pacts.by_element[element] or {}) do list[#list + 1] = name end
    end
    return list
end

return burst_pacts
