# %% Jupyter Notebook | Julia 1.10.0 @ julia | format 2~4
# % language_info: {"file_extension":".jl","mimetype":"application/julia","name":"julia","version":"1.10.0"}
# % kernelspec: {"name":"julia-1.10","display_name":"Julia 1.10.0","language":"julia"}
# % nbformat: 4
# % nbformat_minor: 2

# %% [1] markdown
# # TWayFoil.jl

# %% [2] markdown
# 🎯主要功能：PNG图像 ⇌ 任意文件
# 
# - ✨PNG加壳：使用ARGB PNG**图像**【加密】**任意文件**
# - 🌟PNG解壳：【还原】ARGB PNG**图像**为**普通文件**

# %% [3] markdown
# ## 建立模块上下文

# %% [4] code
module TWayFoil


# %% [5] markdown
# ## PNG API

# %% [6] code
using PNGFiles
using ColorTypes










# %% [16] markdown
# ## 32位ARGB转换⇒PNG转文件





# %% [21] markdown
# 升级版——自动识别尾部「不足四字节」的部分
# 
# - 这些可能是其它文件转换成的PNG

# %% [22] code
"""
识别并裁剪PNG「自动补足」的字节
- 📌按照【固定添加】的末尾字节，计算「先前转换成ARGB PNG时，因『4字节需要』而【多新增】的字节数」
    - 此处仅需一个字节，并且这个字节固定在最后
    - 所有可能取值为：0x01~0x04
        - 下限/0x01：添加该字节后正好，只需删掉本身（已经算入在pop!里边了）
        - 上限/0x04：添加该字节后冗余3个字节，该字节和其它仨（一般为空）组成了新ARGB像素
    - 其它范围外取值：返回自身
"""
function strip_raw_by_last_pixel!(raw8::Vector{UInt8})
    # * 利用【固定添加】获取末尾「新增数」
    local num_surplussed_bytes = raw8[end]
    # 使用「新增数+1」进行【截取】
    if num_surplussed_bytes in 0x01:0x04
        for _ in 1:num_surplussed_bytes
            pop!(raw8)
        end
    end
    # 返回
    raw8
end

"适应其它类型，如生成器"
strip_raw_by_last_pixel(raw8) = raw8 |> collect |> strip_raw_by_last_pixel!


export png2raw # * 导出核心函数

"""
    png2raw(目标类型or目标路径, 待转换对象)
PNG⇒文件
- 📌将PNG按照「先行后列」的方式扫描，并返回字节串
- 📌核心流程：图片路径⇒像素矩阵⇒字节串⇒文件
"""
function png2raw end

# 图片⇒矩阵
png2raw(from::AbstractString) = png2raw(
    replace(from, r".png$" => ""),
    from
)
png2raw(destination, from::AbstractString) = png2raw(
    destination,
    PNGFiles.load(from) # 加载出一个矩阵
)

# 矩阵⇒向量
function png2raw(png::Matrix)
    # * 开始计算、存储并返回ARGB序列 * #
    local raw8 = UInt8[]
    local argb::ARGB

    # * 先注入长度
    for row in eachcol(png)
        for pixel in row
            # 动态获取像素
            argb = ARGB(pixel)
            # 一个像素转换成四个字节
            push!(raw8,
                UInt8(round(argb.alpha * 0xff)),
                UInt8(round(argb.r     * 0xff)),
                UInt8(round(argb.g     * 0xff)),
                UInt8(round(argb.b     * 0xff)),
            )
        end
    end
    
    # * 后进行截取
    return strip_raw_by_last_pixel!(raw8)
end
png2raw(destination, png::Matrix) = png2raw(destination, #= 矩阵⇒向量 =#png2raw(png))

# 向量⇒文件|向量
png2raw(::Type{<:Vector}, raw::Vector) = raw # * 向量类型⇒自身
png2raw(destination::AbstractString, raw::Vector) = write(
    destination,
    raw
)



# %% [23] markdown
# ## 文件⇒PNG


# %% [25] code
# 使用N0f8转换
using ColorTypes: reinterpret, N0f8

# %% [26] markdown
# 字节串⇒像素序列

# %% [27] code
"""
计算「自动补足」过程中需要补足的「空白字节」个数
- 📌除了最后一个表示「转换时补足的字节个数」的字节，其它都为「空白字节」
    - ⚠️其数目可能为零
"""
n_complement_blank_bytes(len::Integer) = 3 - (len & 0b11)

"""
更通用地计算「自动补足n字节单元」所需的「空白字节数」
"""
n_complement_blank_bytes(len::Integer, n::Unsigned) = (n - 1) - (len & 0b11)


"""
自动补足
- 📌按照`png2raw`的思路，对字节串进行「四位补足」
    - 一定会【补足】一个像素，故字节值必定大于零
"""
function complete_4_bytes!(raw::AbstractVector{UInt8})
    # 根据个数补足「空白字符」
    local n_blank_bytes::UInt8 = n_complement_blank_bytes(length(raw))
    for _ in 1:n_blank_bytes
        push!(raw, UInt8(0))
    end

    # 添加 | 这时候要算上其自身
    push!(raw, UInt8(n_blank_bytes + 1))

    # 返回空 | 断言`@assert (length(v) & 0b11) == 0b0 raw`一定成立
    nothing
end


"""
字节串⇒像素序列
- 📌首先进行「自动补足」（破坏性操作！）
- 然后「四位转换」
"""
function raw2argb!(raw::AbstractVector{UInt8})::Vector{ARGB{N0f8}}
    # 自动补足
    complete_4_bytes!(raw)
    # 四个一批转换
    local result = ARGB{N0f8}[] # !【2024-01-21 23:54:57】后续必须得是`Matrix{ARGB{N0f8}}`类型才能被存储
    for i in 0:((length(raw) >> 2 #= 像素个数 =#) - 1)
        push!(result, ARGB{N0f8}(
            reinterpret(N0f8, raw[(i << 2) + 2]), # R
            reinterpret(N0f8, raw[(i << 2) + 3]), # G
            reinterpret(N0f8, raw[(i << 2) + 4]), # B
            reinterpret(N0f8, raw[(i << 2) + 1]), # A # ! 在最前面
        ))
    end
    result
end



# %% [28] markdown
# 像素序列⇒像素矩阵

# %% [29] code
"""
分解整数为「两个相近整数的乘积」
- 🎯根据像素序列计算最终图像尺寸
    - 原则：图像尽可能【方正】而非【扁长】
- 📌使用质因数分解，从开根往小处过滤
    - 第一个数 ≤ 第二个数
"""
function size_1to2(n::I)::Tuple{I,I} where {I <: Integer}
    # 首先开根
    local n1::I = I(floor(sqrt(n)))
    # 然后递减
    while !iszero(n % n1) && n1 > 0
        n1 -= 1
    end
    # 最后相除返回
    return (n1, n ÷ n1)
end


"""
重整化「像素向量」
- 📌需要保留其中像素的类型
    - 只有类似`Matrix{ARGB{N0f8}}`的类型才能被save
"""
reshape_pixels(pixels::Vector{T}) where T = Matrix{T}(reshape(pixels, size_1to2(length(pixels))))



# %% [30] code
export raw2png!, raw2png # * 导出核心函数

"""
    raw2png(目标类型or目标路径, 待转换对象)
将文件转换为图片
- 📌主要流程：文件路径⇒字节串（向量）⇒像素矩阵（图像）|图片路径
"""
function raw2png end

# 文件⇒向量
raw2png(from::AbstractString) = raw2png("$from.png", from)
raw2png(destination, from::AbstractString) = raw2png(
    destination,
    from |> read
)

# 向量⇒矩阵
raw2png!(::Type{<:Vector}, raw::Vector{UInt8}) = raw # * 若指定输出格式为「向量」，则返回自身
raw2png!(destination, raw::Vector{UInt8}) = raw2png(
    destination,
    raw |> raw2argb! |> reshape_pixels
)
raw2png(destination, raw::Vector{UInt8}) = raw2png!(destination, copy(raw))

# 矩阵⇒自身|文件
raw2png(::Type{<:Matrix}, image::Matrix) = image # * 若指定输出格式为「矩阵」，则返回自身
raw2png(destination::AbstractString, image::Matrix) = PNGFiles.save(destination, image)



# %% [31] markdown
# ## 关闭模块上下文

# %% [32] code
end # module


# %% [33] markdown
# ## 尝试自编译


