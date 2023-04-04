# defmodule Lively.Media.Face do
#   def detect do
#     {backend, target} = Evision.Zoo.to_quoted_backend_and_target(attrs)

#     opts = [
#       top_k: attrs["top_k"],
#       nms_threshold: attrs["nms_threshold"],
#       conf_threshold: attrs["conf_threshold"],
#       backend: backend,
#       target: target
#     ]

#     model =
#       case attrs["variant_id"] do
#         "yunet_quant" ->
#           :quant_model

#         _ ->
#           :default_model
#       end

#     [
#       quote do
#         model = Evision.Zoo.FaceDetection.YuNet.init(unquote(model), unquote(opts))
#       end,
#       quote do
#         image_input = Kino.Input.image("Image")
#         form = Kino.Control.form([image: image_input], submit: "Run")

#         frame = Kino.Frame.new()

#         form
#         |> Kino.Control.stream()
#         |> Stream.filter(& &1.data.image)
#         |> Kino.listen(fn %{data: %{image: image}} ->
#           Kino.Frame.render(frame, Kino.Markdown.new("Running..."))

#           image = Evision.Mat.from_binary(image.data, {:u, 8}, image.height, image.width, 3)
#           results = Evision.Zoo.FaceDetection.YuNet.infer(model, image)

#           image = Evision.cvtColor(image, Evision.Constant.cv_COLOR_RGB2BGR())

#           Evision.Zoo.FaceDetection.YuNet.visualize(image, results)
#           |> then(&Kino.Frame.render(frame, Kino.Image.new(Evision.imencode(".png", &1), :png)))
#         end)

#         Kino.Layout.grid([form, frame], boxed: true, gap: 16)
#       end
#     ]
#   end
# end
