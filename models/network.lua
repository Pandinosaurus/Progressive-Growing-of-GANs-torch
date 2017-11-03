-- script for dealing with network
-- resl: resolution-level (log2 scale)


require 'nn'
require 'cunn'
require 'cudnn'
require 'cutorch'
require 'math'
require 'models.custom_layer'
local G = require 'models.gen'
local D = require 'models.dis'


local network = {}


-- grow network
function network.grow_network(gen, dis, resl, g_config, d_config, use_cuda)

    local use_cuda = use_cuda or true
    assert(type(use_cuda)=='boolean', 'use_cuda flag = true/false')

    -- flush previous fade-in layer first.
    --network.flush_FadeInBlock(gen, dis, resl)
    
    -- attach new fade-in layer to the last.
    if resl >2 and resl < 10 then
        network.attach_FadeInBlock(gen, dis, resl, g_config, d_config)
    end
    if use_cuda then gen:cuda(); dis:cuda(); end
    return gen, dis
end


function network.attach_FadeInBlock(gen, dis, resl, g_config, d_config)
    -- generator.
    -- make deep copy of last block and delete it.
    print(string.format('[From:%d, To:%d] Growing networks ... It might take few seconds... [Generator]',
                                                                            math.pow(2,resl), math.pow(2,resl+1)))
    local transition_tick = g_config['transition_tick']                                                                        
    low_res_block = gen.modules[resl-1]:clone()
    gen:remove()
    -- now, make residual block and add fade-in layer.
    local inter_block, ndim = G.intermediate_block(resl, g_config)
    local output_block = G.output_block(ndim, g_config)
    local fadein = nn.Sequential()
    fadein:add( nn.ConcatTable()
                :add(nn.Sequential():add(low_res_block):add(nn.SpatialUpSamplingNearest(2.0)))  -- for low resl
                :add(nn.Sequential():add(inter_block):add(output_block)))                       -- for high resl
    fadein:add(nn.FadeInLayer(transition_tick))
    gen:add(fadein)
    fadein = nil

    -- discriminator
    -- make deep copy of first block and delete it.
    print(string.format('[From:%d, To:%d] Growing networks ... It might take few seconds... [Discriminator]',
                                                                            math.pow(2,resl), math.pow(2,resl+1)))
    low_res_block = dis.modules[1]:clone()
    dis:remove(1)
    -- now, make residual block and add fade-in layer.
    local inter_block, ndim = D.intermediate_block(resl, d_config)
    local input_block = D.input_block(ndim, d_config)
    local fadein = nn.Sequential()
    fadein:add( nn.ConcatTable()
                :add(nn.Sequential():add(low_res_block):add(nn.SpatialAveragePooling(2,2,2,2)))
                :add(nn.Sequential():add(input_block):add(inter_block)))
    fadein:add(nn.FadeInLayer(transition_tick))
    dis:insert(fadein,1)
    fadein = nil

    return gen, dis
end

function network.flush_FadeInBlock(gen, dis, resl)
    -- remove from generator and discriminator.
    -- replace fade-in block with intermediate block.
    -- need to copy weights befroe the removal.
    if resl>=3 and resl<=9 then 
        local high_resl_block = gen.modules[resl-1].modules[1].modules[2]:clone()
        gen:remove()
        gen:add(high_resl_block.modules[1])
        gen:add(high_resl_block.modules[2])
        local high_resl_block = dis.modules[1].modules[1].modules[2]:clone()
        dis:remove(1)
        dis:insert(high_resl_block.modules[2], 1)
        dis:insert(high_resl_block.modules[1], 1)
    end
    return gen, dis
end


-- return initial structure of generator.
function network.get_init_gen(g_config)
    local model = nn.Sequential()
    local input_block, ndim = G.input_block(g_config)
    model:add(input_block)
    model:add(G.output_block(ndim, g_config))
    return model
end

-- return initial structure of discriminator.
function network.get_init_dis(d_config)
    local model = nn.Sequential()
    local output_block, ndim = D.output_block(d_config) 
    model:add(D.input_block(ndim, d_config))
    model:add(output_block)
    return model
end

return network


