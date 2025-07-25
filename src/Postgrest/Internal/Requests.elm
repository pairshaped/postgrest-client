module Postgrest.Internal.Requests exposing
    ( Request(..)
    , RequestType(..)
    , defaultRequest
    , fullURL
    , mapRequest
    , requestTypeToBody
    , requestTypeToHTTPMethod
    , requestTypeToHeaders
    , setCustomHeaders
    , setMandatoryParams
    , setTimeout
    )

import Http
import Json.Decode exposing (Decoder)
import Json.Encode as JE
import Postgrest.Internal.Endpoint as Endpoint exposing (Endpoint)
import Postgrest.Internal.JWT exposing (JWT, jwtHeader)
import Postgrest.Internal.Params exposing (Params, concatParams, toQueryString)
import Postgrest.Internal.URL exposing (BaseURL, baseURLToString)


type Request r
    = Request (RequestOptions r)


type alias RequestOptions r =
    { options : RequestType r
    , timeout : Maybe Float
    , defaultParams : Params
    , overrideParams : Params
    , mandatoryParams : Params
    , baseURL : BaseURL
    , customHeaders : List Http.Header
    }


type RequestType r
    = Post JE.Value (Decoder r)
    | Patch JE.Value (Decoder r)
    | Get (Decoder r)
    | Delete r


defaultRequest : Endpoint b -> RequestType a -> Request a
defaultRequest e requestType =
    Request
        { options = requestType
        , timeout = Nothing
        , defaultParams = Endpoint.defaultParams e
        , overrideParams = []
        , mandatoryParams = []
        , baseURL = Endpoint.url e
        , customHeaders = []
        }


requestTypeToHeaders : Maybe JWT -> RequestType r -> List Http.Header -> List Http.Header
requestTypeToHeaders jwt_ r customHeaders =
    let
        defaultHeaders =
            case r of
                Post _ _ ->
                    [ jwtHeader jwt_, Just returnRepresentationHeader ]

                Patch _ _ ->
                    [ jwtHeader jwt_, Just returnRepresentationHeader ]

                Get _ ->
                    [ jwtHeader jwt_ ]

                Delete _ ->
                    [ jwtHeader jwt_

                    -- Even though we don't need the record to be returned, this is a
                    -- temporary workaround for when defaultSelect is specified, because
                    -- if a select is specified without "Prefer" "return=representation"
                    -- postgrest will give us an error that looks like this:
                    --
                    -- {
                    --     "hint": null,
                    --     "details": null,
                    --     "code": "42703",
                    --     "message": "column pg_source.id does not exist"
                    -- }
                    , Just returnRepresentationHeader
                    ]
    in
    List.filterMap identity defaultHeaders ++ customHeaders


requestTypeToBody : RequestType r -> Http.Body
requestTypeToBody r =
    case r of
        Delete _ ->
            Http.emptyBody

        Get _ ->
            Http.emptyBody

        Post body _ ->
            Http.jsonBody body

        Patch body _ ->
            Http.jsonBody body


requestTypeToHTTPMethod : RequestType r -> String
requestTypeToHTTPMethod r =
    case r of
        Post _ _ ->
            "POST"

        Patch _ _ ->
            "PATCH"

        Delete _ ->
            "DELETE"

        Get _ ->
            "GET"


setMandatoryParams : Params -> Request a -> Request a
setMandatoryParams p =
    mapRequest (\req -> { req | mandatoryParams = p })


returnRepresentationHeader : Http.Header
returnRepresentationHeader =
    Http.header "Prefer" "return=representation"


mapRequest : (RequestOptions a -> RequestOptions a) -> Request a -> Request a
mapRequest f (Request options) =
    Request (f options)


fullURL : RequestOptions r -> String
fullURL { defaultParams, overrideParams, mandatoryParams, baseURL } =
    let
        params =
            concatParams [ defaultParams, overrideParams, mandatoryParams ]
    in
    [ baseURLToString baseURL, toQueryString params ]
        |> List.filter (String.isEmpty >> Basics.not)
        |> String.join "?"


setTimeout : Float -> Request a -> Request a
setTimeout t =
    mapRequest (\req -> { req | timeout = Just t })


setCustomHeaders : List Http.Header -> Request a -> Request a
setCustomHeaders headers =
    mapRequest (\req -> { req | customHeaders = headers })
