-- Green TD - port of the Warcraft III map "Green TD v36.0" (by Sencility) to Dota 2.
require("gtd/init")

function Precache(context)
	GTD:Precache(context)
end

function Activate()
	GTD:Init()
end
