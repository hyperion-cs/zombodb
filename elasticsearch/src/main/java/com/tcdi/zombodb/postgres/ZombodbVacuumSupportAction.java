/*
 * Copyright 2017 ZomboDB, LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package com.tcdi.zombodb.postgres;

import com.tcdi.zombodb.query_parser.utils.Utils;
import org.elasticsearch.action.admin.indices.refresh.RefreshRequestBuilder;
import org.elasticsearch.action.admin.indices.refresh.RefreshResponse;
import org.elasticsearch.action.search.*;
import org.elasticsearch.client.Client;
import org.elasticsearch.client.node.NodeClient;
import org.elasticsearch.common.inject.Inject;
import org.elasticsearch.common.settings.Settings;
import org.elasticsearch.common.unit.TimeValue;
import org.elasticsearch.rest.*;
import org.elasticsearch.search.SearchHit;

import java.io.IOException;

import static com.tcdi.zombodb.postgres.PostgresTIDResponseAction.INVALID_BLOCK_NUMBER;
import static com.tcdi.zombodb.query.ZomboDBQueryBuilders.visibility;
import static org.elasticsearch.rest.RestRequest.Method.GET;
import static org.elasticsearch.rest.RestRequest.Method.POST;

public class ZombodbVacuumSupportAction extends BaseRestHandler {

    @Inject
    public ZombodbVacuumSupportAction(Settings settings, RestController controller) {
        super(settings);
        controller.registerHandler(GET, "/{index}/_zdbvacuum", this);
        controller.registerHandler(POST, "/{index}/_zdbvacuum", this);
    }

    @Override
    protected RestChannelConsumer prepareRequest(RestRequest request, NodeClient client) throws IOException {
        String index = request.param("index");
        long xmin = request.paramAsLong("xmin", 0);
        long xmax = request.paramAsLong("xmax", 0);
        int commandid = request.paramAsInt("commandid", -1);
        String[] tmp = request.paramAsStringArray("active", new String[]{"0"});
        long[] active = new long[tmp.length];
        for (int i = 0; i < tmp.length; i++)
            active[i] = Long.valueOf(tmp[i]);

        // return the ctid (_id) of every document we think might be invisible to us
        // based on the current state of the underlying index
        SearchRequestBuilder search = SearchAction.INSTANCE.newRequestBuilder(client)
                .setIndices(index)
                .setTypes("data")
                .setScroll(TimeValue.timeValueMinutes(10))
                .setSize(10000)
                .setQuery(
                        visibility()
                                .xmin(xmin)
                                .xmax(xmax)
                                .commandId(commandid)
                                .activeXids(active)
                );

        byte[] bytes = null;
        int total = 0, cnt = 0, offset = 0;
        SearchResponse response = null;
        while (true) {
            if (response == null) {
                response = client.execute(SearchAction.INSTANCE, search.request()).actionGet();
                total = (int) response.getHits().getTotalHits();
                bytes = new byte[8 + 6 * total];
                offset += Utils.encodeLong(total, bytes, offset);
            } else {
                response = client.execute(SearchScrollAction.INSTANCE,
                        SearchScrollAction.INSTANCE.newRequestBuilder(client)
                                .setScrollId(response.getScrollId())
                                .setScroll(TimeValue.timeValueMinutes(10))
                                .request()).actionGet();
            }

            for (SearchHit hit : response.getHits()) {
                String id;
                int blockno;
                char rowno;

                try {
                    id = hit.id();

                    int dash = id.indexOf('-', 1);
                    blockno = Integer.parseInt(id.substring(0, dash), 10);
                    rowno = (char) Integer.parseInt(id.substring(dash + 1), 10);
                } catch (Exception nfe) {
                    logger.warn("hit.id()=/" + hit.id() + "/ is not in the proper format.  Defaulting to INVALID_BLOCK_NUMBER");
                    blockno = INVALID_BLOCK_NUMBER;
                    rowno = 0;
                }

                offset += Utils.encodeInteger(blockno, bytes, offset);
                offset += Utils.encodeCharacter(rowno, bytes, offset);
                cnt++;
            }

            if (cnt == total)
                break;
        }

        byte[] finalBytes = bytes;
        return channel -> channel.sendResponse(new BytesRestResponse(RestStatus.OK, "application/data", finalBytes));
    }

    @Override
    public boolean supportsPlainText() {
        return true;
    }
}